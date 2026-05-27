#include "tx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "account.h"
#include "category.h"
#include "db.h"
#include "util.h"

static int tx_list(sqlite3 *db, const char *account, const char *month,
                   const char *category, int limit)
{
	char sql[1024];
	int n = snprintf(sql, sizeof sql,
		"SELECT t.id, a.name, t.date, t.description, t.amount_cents, "
		"  COALESCE(c.name, '?') "
		"FROM transactions t "
		"JOIN accounts a ON a.id = t.account_id "
		"LEFT JOIN categories c ON c.id = t.category_id "
		"WHERE 1=1");
	if (account) n += snprintf(sql + n, sizeof sql - n, " AND a.name = ?");
	if (month)   n += snprintf(sql + n, sizeof sql - n, " AND substr(t.date,1,7) = ?");
	if (category) {
		if (strcmp(category, "?") == 0 || strcasecmp(category, "unknown") == 0)
			n += snprintf(sql + n, sizeof sql - n, " AND t.category_id IS NULL");
		else
			n += snprintf(sql + n, sizeof sql - n,
				" AND c.name = ? COLLATE NOCASE");
	}
	n += snprintf(sql + n, sizeof sql - n, " ORDER BY t.date, t.id LIMIT ?;");

	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	int bi = 1;
	if (account) db_bind_text(stmt, bi++, account);
	if (month) db_bind_text(stmt, bi++, month);
	if (category && !(strcmp(category, "?") == 0 ||
	                  strcasecmp(category, "unknown") == 0)) {
		db_bind_text(stmt, bi++, category);
	}
	sqlite3_bind_int(stmt, bi++, limit);

	printf("%-5s  %-16s  %-10s  %-40s  %10s  %s\n",
	       "ID", "ACCOUNT", "DATE", "DESCRIPTION", "AMOUNT", "CATEGORY");
	long long count = 0;
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		char amt[32];
		util_format_amount(sqlite3_column_int64(stmt, 4), amt, sizeof amt);
		printf("%-5lld  %-16.16s  %-10s  %-40.40s  %10s  %s\n",
		       (long long)sqlite3_column_int64(stmt, 0),
		       sqlite3_column_text(stmt, 1),
		       sqlite3_column_text(stmt, 2),
		       sqlite3_column_text(stmt, 3),
		       amt,
		       sqlite3_column_text(stmt, 5));
		count++;
	}
	sqlite3_finalize(stmt);
	printf("(%lld row%s)\n", count, count == 1 ? "" : "s");
	return 0;
}

static int tx_add(sqlite3 *db, const char *account, const char *date_in,
                  const char *desc, const char *amount_in, const char *category)
{
	if (!account || !date_in || !desc || !amount_in) {
		fprintf(stderr,
		        "usage: treasury tx add --account <name> --date <YYYY-MM-DD> "
		        "--desc <text> --amount <amount> [--category <name>]\n");
		return 2;
	}

	long long account_id = account_find_id(db, account);
	if (account_id < 0) {
		fprintf(stderr, "treasury: unknown account '%s'\n", account);
		return 1;
	}

	char date_iso[11];
	if (util_normalize_date(date_in, date_iso) != 0) {
		fprintf(stderr, "treasury: invalid --date '%s' (expect YYYY-MM-DD)\n",
		        date_in);
		return 1;
	}

	int64_t cents = 0;
	if (util_parse_amount(amount_in, &cents) != 0) {
		fprintf(stderr, "treasury: invalid --amount '%s'\n", amount_in);
		return 1;
	}

	long long category_id = -1;
	if (category && *category) {
		category_id = category_get_or_create(db, category);
		if (category_id < 0) {
			fprintf(stderr, "treasury: could not resolve category '%s'\n",
			        category);
			return 1;
		}
	}

	const char *sql =
		"INSERT INTO transactions"
		"(account_id, date, description, amount_cents, category_id, import_batch_id) "
		"VALUES(?, ?, ?, ?, ?, NULL);";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	sqlite3_bind_int64(stmt, 1, account_id);
	db_bind_text(stmt, 2, date_iso);
	db_bind_text(stmt, 3, desc);
	sqlite3_bind_int64(stmt, 4, cents);
	if (category_id > 0) sqlite3_bind_int64(stmt, 5, category_id);
	else sqlite3_bind_null(stmt, 5);

	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	if (rc != SQLITE_DONE) {
		if (rc == SQLITE_CONSTRAINT) {
			fprintf(stderr,
			        "treasury: duplicate: same account/date/description/amount "
			        "already exists\n");
		} else {
			fprintf(stderr, "treasury: could not add transaction: %s\n",
			        sqlite3_errmsg(db));
		}
		return 1;
	}

	char details[512];
	if (category && *category) {
		snprintf(details, sizeof details,
		         "account=%s date=%s amount=%lld category=%s",
		         account, date_iso, (long long)cents, category);
	} else {
		snprintf(details, sizeof details,
		         "account=%s date=%s amount=%lld",
		         account, date_iso, (long long)cents);
	}
	db_audit(db, "tx.add", details);

	char amt[32];
	util_format_amount(cents, amt, sizeof amt);
	printf("added transaction: %s | %s | %s | %s\n",
	       date_iso, account, desc, amt);
	return 0;
}

int cmd_tx(sqlite3 *db, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr, "usage: treasury tx <list|add> ...\n");
		return 2;
	}
	if (strcmp(argv[0], "add") == 0) {
		const char *account = NULL, *date = NULL, *desc = NULL;
		const char *amount = NULL, *category = NULL;
		for (int i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--account") == 0 && i + 1 < argc) account = argv[++i];
			else if (strcmp(argv[i], "--date") == 0 && i + 1 < argc) date = argv[++i];
			else if (strcmp(argv[i], "--desc") == 0 && i + 1 < argc) desc = argv[++i];
			else if (strcmp(argv[i], "--amount") == 0 && i + 1 < argc) amount = argv[++i];
			else if (strcmp(argv[i], "--category") == 0 && i + 1 < argc) category = argv[++i];
			else {
				fprintf(stderr, "treasury: unknown tx add flag: %s\n", argv[i]);
				return 2;
			}
		}
		return tx_add(db, account, date, desc, amount, category);
	}
	if (strcmp(argv[0], "list") == 0) {
		const char *account = NULL, *month = NULL, *category = NULL;
		int limit = 200;
		for (int i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--account") == 0 && i + 1 < argc)  account = argv[++i];
			else if (strcmp(argv[i], "--month") == 0 && i + 1 < argc) month = argv[++i];
			else if (strcmp(argv[i], "--category") == 0 && i + 1 < argc) category = argv[++i];
			else if (strcmp(argv[i], "--limit") == 0 && i + 1 < argc) limit = atoi(argv[++i]);
			else {
				fprintf(stderr, "treasury: unknown tx flag: %s\n", argv[i]);
				return 2;
			}
		}
		if (month && util_valid_year_month(month) != 0) {
			fprintf(stderr, "treasury: invalid --month '%s' (expect YYYY-MM)\n", month);
			return 2;
		}
		if (account && account_find_id(db, account) < 0) {
			fprintf(stderr, "treasury: unknown account '%s'\n", account);
			return 1;
		}
		if (limit <= 0) limit = 200;
		return tx_list(db, account, month, category, limit);
	}
	fprintf(stderr, "treasury: unknown tx subcommand '%s'\n", argv[0]);
	return 2;
}
