#include "import.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "account.h"
#include "csv.h"
#include "db.h"
#include "util.h"

/* Header detection: locate the date/description/amount columns.
   Two amount styles are supported:
     * single "amount" column, signed
     * separate "debit"/"credit" columns: signed = credit - debit */
typedef struct {
	int date_col;
	int desc_col;
	int amount_col;
	int debit_col;
	int credit_col;
} header_map;

static int header_match(const char *cell, const char *want)
{
	if (!cell || !want) return 0;
	while (*cell && (*cell == ' ' || *cell == '"')) cell++;
	const char *end = cell + strlen(cell);
	while (end > cell && (end[-1] == ' ' || end[-1] == '"')) end--;
	size_t n = (size_t)(end - cell);
	size_t wn = strlen(want);
	if (n != wn) return 0;
	for (size_t i = 0; i < n; i++) {
		if (tolower((unsigned char)cell[i]) != tolower((unsigned char)want[i]))
			return 0;
	}
	return 1;
}

static int detect_headers(csv_reader *r, header_map *h)
{
	h->date_col = h->desc_col = h->amount_col = h->debit_col = h->credit_col = -1;
	for (int i = 0; i < r->field_count; i++) {
		const char *f = r->fields[i];
		if (h->date_col < 0 &&
		    (header_match(f, "date") ||
		     header_match(f, "transaction date") ||
		     header_match(f, "posting date") ||
		     header_match(f, "post date") ||
		     header_match(f, "trans date"))) {
			h->date_col = i;
		} else if (h->desc_col < 0 &&
		           (header_match(f, "description") ||
		            header_match(f, "name") ||
		            header_match(f, "memo") ||
		            header_match(f, "payee") ||
		            header_match(f, "details"))) {
			h->desc_col = i;
		} else if (h->amount_col < 0 && header_match(f, "amount")) {
			h->amount_col = i;
		} else if (h->debit_col < 0 &&
		           (header_match(f, "debit") || header_match(f, "withdrawal"))) {
			h->debit_col = i;
		} else if (h->credit_col < 0 &&
		           (header_match(f, "credit") || header_match(f, "deposit"))) {
			h->credit_col = i;
		}
	}
	if (h->date_col < 0 || h->desc_col < 0) return -1;
	if (h->amount_col < 0 && (h->debit_col < 0 && h->credit_col < 0)) return -1;
	return 0;
}

int cmd_import(sqlite3 *db, int argc, char **argv)
{
	const char *file = NULL;
	const char *account = NULL;
	int dry_run = 0;

	for (int i = 0; i < argc; i++) {
		if (strcmp(argv[i], "--account") == 0 && i + 1 < argc) {
			account = argv[++i];
		} else if (strcmp(argv[i], "--dry-run") == 0) {
			dry_run = 1;
		} else if (argv[i][0] != '-') {
			if (!file) file = argv[i];
		} else {
			fprintf(stderr, "treasury: unknown import flag: %s\n", argv[i]);
			return 2;
		}
	}
	if (!file || !account) {
		fprintf(stderr,
		        "usage: treasury import <file.csv> --account <name> [--dry-run]\n");
		return 2;
	}

	long long account_id = account_find_id(db, account);
	if (account_id < 0) {
		fprintf(stderr, "treasury: unknown account '%s'\n", account);
		return 1;
	}

	csv_reader r;
	if (csv_open(&r, file) != 0) {
		fprintf(stderr, "treasury: cannot open %s\n", file);
		return 1;
	}

	if (csv_next(&r) != 1) {
		fprintf(stderr, "treasury: %s is empty\n", file);
		csv_close(&r);
		return 1;
	}
	header_map h;
	if (detect_headers(&r, &h) != 0) {
		fprintf(stderr,
		        "treasury: could not find required headers in %s\n"
		        "  need columns: date, description, and (amount or debit/credit)\n",
		        file);
		csv_close(&r);
		return 1;
	}

	long long batch_id = -1;
	if (!dry_run) {
		const char *bsql =
			"INSERT INTO import_batches(filename, account_id, row_count, status) "
			"VALUES(?, ?, 0, 'in_progress');";
		sqlite3_stmt *bstmt = NULL;
		if (sqlite3_prepare_v2(db, bsql, -1, &bstmt, NULL) != SQLITE_OK) {
			csv_close(&r);
			return 1;
		}
		db_bind_text(bstmt, 1, file);
		sqlite3_bind_int64(bstmt, 2, account_id);
		if (sqlite3_step(bstmt) != SQLITE_DONE) {
			sqlite3_finalize(bstmt);
			csv_close(&r);
			return 1;
		}
		sqlite3_finalize(bstmt);
		batch_id = sqlite3_last_insert_rowid(db);
	}

	const char *isql =
		"INSERT OR IGNORE INTO transactions"
		"(account_id, date, description, amount_cents, import_batch_id) "
		"VALUES(?, ?, ?, ?, ?);";
	sqlite3_stmt *istmt = NULL;
	if (sqlite3_prepare_v2(db, isql, -1, &istmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare insert failed: %s\n", sqlite3_errmsg(db));
		csv_close(&r);
		return 1;
	}

	long long total = 0, inserted = 0, duplicates = 0, rejected = 0;
	db_exec(db, "BEGIN;");

	while (csv_next(&r) == 1) {
		total++;
		if (r.field_count <= h.date_col || r.field_count <= h.desc_col) {
			rejected++;
			fprintf(stderr, "  reject line %ld: not enough columns\n", r.line_number);
			continue;
		}
		char date_iso[11];
		if (util_normalize_date(r.fields[h.date_col], date_iso) != 0) {
			rejected++;
			fprintf(stderr, "  reject line %ld: bad date '%s'\n",
			        r.line_number, r.fields[h.date_col]);
			continue;
		}
		char *desc = util_trim(r.fields[h.desc_col]);
		if (!desc || !*desc) {
			rejected++;
			fprintf(stderr, "  reject line %ld: empty description\n", r.line_number);
			continue;
		}

		int64_t cents = 0;
		int amount_ok = 0;
		if (h.amount_col >= 0 && r.field_count > h.amount_col) {
			const char *raw = r.fields[h.amount_col];
			if (raw && *util_trim((char *)raw)) {
				if (util_parse_amount(raw, &cents) == 0) amount_ok = 1;
			}
		}
		if (!amount_ok && (h.debit_col >= 0 || h.credit_col >= 0)) {
			int64_t debit = 0, credit = 0;
			int had_any = 0;
			if (h.debit_col >= 0 && r.field_count > h.debit_col) {
				char *raw = (char *)r.fields[h.debit_col];
				if (raw && *util_trim(raw)) {
					if (util_parse_amount(raw, &debit) == 0) had_any = 1;
				}
			}
			if (h.credit_col >= 0 && r.field_count > h.credit_col) {
				char *raw = (char *)r.fields[h.credit_col];
				if (raw && *util_trim(raw)) {
					if (util_parse_amount(raw, &credit) == 0) had_any = 1;
				}
			}
			if (had_any) {
				/* debit reduces balance, credit increases. Many bank CSVs export
				   debit as a positive number, so subtract. */
				if (debit < 0) debit = -debit;
				if (credit < 0) credit = -credit;
				cents = credit - debit;
				amount_ok = 1;
			}
		}
		if (!amount_ok) {
			rejected++;
			fprintf(stderr, "  reject line %ld: bad amount\n", r.line_number);
			continue;
		}

		if (dry_run) {
			char buf[32];
			util_format_amount(cents, buf, sizeof buf);
			printf("  would import: %s | %-40.40s | %s\n", date_iso, desc, buf);
			inserted++;
			continue;
		}

		sqlite3_bind_int64(istmt, 1, account_id);
		db_bind_text(istmt, 2, date_iso);
		db_bind_text(istmt, 3, desc);
		sqlite3_bind_int64(istmt, 4, cents);
		sqlite3_bind_int64(istmt, 5, batch_id);
		int rc = sqlite3_step(istmt);
		if (rc != SQLITE_DONE) {
			rejected++;
			fprintf(stderr, "  reject line %ld: insert error\n", r.line_number);
		} else if (sqlite3_changes(db) == 0) {
			duplicates++;
		} else {
			inserted++;
		}
		sqlite3_reset(istmt);
		sqlite3_clear_bindings(istmt);
	}

	db_exec(db, "COMMIT;");
	sqlite3_finalize(istmt);
	csv_close(&r);

	if (!dry_run) {
		const char *usql =
			"UPDATE import_batches SET row_count = ?, status = ? WHERE id = ?;";
		sqlite3_stmt *ustmt = NULL;
		if (sqlite3_prepare_v2(db, usql, -1, &ustmt, NULL) == SQLITE_OK) {
			sqlite3_bind_int64(ustmt, 1, inserted);
			db_bind_text(ustmt, 2, rejected ? "completed_with_errors" : "completed");
			sqlite3_bind_int64(ustmt, 3, batch_id);
			sqlite3_step(ustmt);
			sqlite3_finalize(ustmt);
		}
		char details[512];
		snprintf(details, sizeof details,
		         "file=%s account=%s rows=%lld inserted=%lld duplicates=%lld rejected=%lld batch=%lld",
		         file, account, total, inserted, duplicates, rejected, batch_id);
		db_audit(db, "import", details);
	}

	printf("imported %lld of %lld rows from %s (account=%s)\n",
	       inserted, total, file, account);
	if (duplicates) printf("  duplicates skipped: %lld\n", duplicates);
	if (rejected)   printf("  rejected: %lld\n", rejected);
	return rejected ? 0 : 0;
}
