#include "export.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "account.h"
#include "db.h"
#include "util.h"

static void csv_print_field(FILE *fp, const char *s)
{
	/* RFC 4180: quote if field contains comma, quote, or newline.
	   Inside quotes, double-up any quote character. */
	int needs_quote = 0;
	for (const char *p = s; *p; p++) {
		if (*p == ',' || *p == '"' || *p == '\n' || *p == '\r') {
			needs_quote = 1; break;
		}
	}
	if (!needs_quote) { fputs(s, fp); return; }
	fputc('"', fp);
	for (const char *p = s; *p; p++) {
		if (*p == '"') fputc('"', fp);  /* escape by doubling */
		fputc(*p, fp);
	}
	fputc('"', fp);
}

static int export_tx(sqlite3 *db, const char *account, const char *month,
                     const char *out_path)
{
	char sql[1024];
	int n = snprintf(sql, sizeof sql,
		"SELECT t.date, a.name, t.description, t.amount_cents, "
		"  COALESCE(c.name, '') "
		"FROM transactions t "
		"JOIN accounts a ON a.id = t.account_id "
		"LEFT JOIN categories c ON c.id = t.category_id "
		"WHERE 1=1");
	if (account) n += snprintf(sql + n, sizeof sql - n, " AND a.name = ?");
	if (month)   n += snprintf(sql + n, sizeof sql - n, " AND substr(t.date,1,7) = ?");
	n += snprintf(sql + n, sizeof sql - n, " ORDER BY t.date, t.id;");

	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	int bi = 1;
	if (account) db_bind_text(stmt, bi++, account);
	if (month)   db_bind_text(stmt, bi++, month);

	FILE *fp = stdout;
	if (out_path) {
		fp = fopen(out_path, "w");
		if (!fp) {
			fprintf(stderr, "treasury: cannot open %s for writing\n", out_path);
			sqlite3_finalize(stmt);
			return 1;
		}
	}

	fputs("date,account,description,amount,category\n", fp);
	long long count = 0;
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		const char *date = (const char *)sqlite3_column_text(stmt, 0);
		const char *acct = (const char *)sqlite3_column_text(stmt, 1);
		const char *desc = (const char *)sqlite3_column_text(stmt, 2);
		char amt[32];
		util_format_amount(sqlite3_column_int64(stmt, 3), amt, sizeof amt);
		const char *cat  = (const char *)sqlite3_column_text(stmt, 4);

		csv_print_field(fp, date ? date : "");
		fputc(',', fp);
		csv_print_field(fp, acct ? acct : "");
		fputc(',', fp);
		csv_print_field(fp, desc ? desc : "");
		fputc(',', fp);
		csv_print_field(fp, amt);
		fputc(',', fp);
		csv_print_field(fp, cat ? cat : "");
		fputc('\n', fp);
		count++;
	}
	sqlite3_finalize(stmt);
	if (fp != stdout) fclose(fp);

	char details[256];
	snprintf(details, sizeof details,
	         "account=%s month=%s rows=%lld out=%s",
	         account ? account : "all",
	         month ? month : "all",
	         count,
	         out_path ? out_path : "stdout");
	db_audit(db, "export.tx", details);
	return 0;
}

static int export_audit(sqlite3 *db, int limit, const char *out_path)
{
	const char *sql_with_limit =
		"SELECT id, created_at, action, COALESCE(details, '') "
		"FROM audit_log ORDER BY id ASC LIMIT ?;";
	const char *sql_all =
		"SELECT id, created_at, action, COALESCE(details, '') "
		"FROM audit_log ORDER BY id ASC;";

	sqlite3_stmt *stmt = NULL;
	const char *sql = (limit > 0) ? sql_with_limit : sql_all;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	if (limit > 0) sqlite3_bind_int(stmt, 1, limit);

	FILE *fp = stdout;
	if (out_path) {
		fp = fopen(out_path, "w");
		if (!fp) {
			fprintf(stderr, "treasury: cannot open %s for writing\n", out_path);
			sqlite3_finalize(stmt);
			return 1;
		}
	}

	fputs("id,when,action,details\n", fp);
	long long count = 0;
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		char idbuf[32];
		snprintf(idbuf, sizeof idbuf, "%lld",
		         (long long)sqlite3_column_int64(stmt, 0));
		const char *when    = (const char *)sqlite3_column_text(stmt, 1);
		const char *action  = (const char *)sqlite3_column_text(stmt, 2);
		const char *details = (const char *)sqlite3_column_text(stmt, 3);

		csv_print_field(fp, idbuf);
		fputc(',', fp);
		csv_print_field(fp, when ? when : "");
		fputc(',', fp);
		csv_print_field(fp, action ? action : "");
		fputc(',', fp);
		csv_print_field(fp, details ? details : "");
		fputc('\n', fp);
		count++;
	}
	sqlite3_finalize(stmt);
	if (fp != stdout) fclose(fp);

	char details[160];
	snprintf(details, sizeof details, "rows=%lld out=%s",
	         count, out_path ? out_path : "stdout");
	db_audit(db, "export.audit", details);
	return 0;
}

int cmd_export(sqlite3 *db, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr,
			"usage: treasury export <tx|audit> [flags]\n"
			"  export tx [--account NAME] [--month YYYY-MM] [--out FILE]\n"
			"  export audit [--limit N] [--out FILE]\n");
		return 2;
	}
	if (strcmp(argv[0], "tx") == 0) {
		const char *account = NULL, *month = NULL, *out_path = NULL;
		for (int i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--account") == 0 && i + 1 < argc) account = argv[++i];
			else if (strcmp(argv[i], "--month") == 0 && i + 1 < argc) month = argv[++i];
			else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_path = argv[++i];
			else {
				fprintf(stderr, "treasury: unknown export tx flag: %s\n", argv[i]);
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
		return export_tx(db, account, month, out_path);
	}
	if (strcmp(argv[0], "audit") == 0) {
		int limit = 0;  /* 0 = no limit */
		const char *out_path = NULL;
		for (int i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--limit") == 0 && i + 1 < argc) {
				limit = atoi(argv[++i]);
				if (limit <= 0) limit = 0;
			}
			else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_path = argv[++i];
			else {
				fprintf(stderr, "treasury: unknown export audit flag: %s\n", argv[i]);
				return 2;
			}
		}
		return export_audit(db, limit, out_path);
	}
	fprintf(stderr, "treasury: unknown export subcommand '%s'\n", argv[0]);
	return 2;
}
