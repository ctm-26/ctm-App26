#include "report.h"

#include <stdio.h>
#include <string.h>

#include "db.h"
#include "util.h"

static int report_month(sqlite3 *db, const char *month)
{
	if (util_valid_year_month(month) != 0) {
		fprintf(stderr, "treasury: invalid month '%s' (expect YYYY-MM)\n", month);
		return 2;
	}

	const char *sql_summary =
		"SELECT "
		"  SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END), "
		"  SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END), "
		"  COUNT(*) "
		"FROM transactions WHERE substr(date,1,7) = ?;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql_summary, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	db_bind_text(stmt, 1, month);
	long long income = 0, spend = 0, count = 0;
	if (sqlite3_step(stmt) == SQLITE_ROW) {
		income = sqlite3_column_int64(stmt, 0);
		spend  = sqlite3_column_int64(stmt, 1);
		count  = sqlite3_column_int64(stmt, 2);
	}
	sqlite3_finalize(stmt);

	printf("\nMonthly report: %s\n", month);
	printf("=========================================\n");
	if (count == 0) {
		printf("(no transactions)\n\n");
		return 0;
	}
	char a[32], b[32], c[32];
	util_format_amount(income, a, sizeof a);
	util_format_amount(spend, b, sizeof b);
	util_format_amount(income + spend, c, sizeof c);
	printf("  transactions : %lld\n", count);
	printf("  income       : %12s\n", a);
	printf("  spending     : %12s\n", b);
	printf("  net          : %12s\n\n", c);

	const char *sql_cat =
		"SELECT COALESCE(c.name, '(unknown)') AS cat, "
		"  SUM(t.amount_cents), COUNT(*) "
		"FROM transactions t "
		"LEFT JOIN categories c ON c.id = t.category_id "
		"WHERE substr(t.date,1,7) = ? "
		"GROUP BY cat ORDER BY SUM(t.amount_cents) ASC;";
	if (sqlite3_prepare_v2(db, sql_cat, -1, &stmt, NULL) != SQLITE_OK) return 1;
	db_bind_text(stmt, 1, month);
	printf("By category:\n");
	printf("  %-20s  %12s  %6s\n", "CATEGORY", "AMOUNT", "COUNT");
	printf("  --------------------  ------------  ------\n");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		char amt[32];
		util_format_amount(sqlite3_column_int64(stmt, 1), amt, sizeof amt);
		printf("  %-20.20s  %12s  %6lld\n",
		       sqlite3_column_text(stmt, 0),
		       amt,
		       (long long)sqlite3_column_int64(stmt, 2));
	}
	sqlite3_finalize(stmt);
	printf("\n");

	const char *sql_acct =
		"SELECT a.name, SUM(t.amount_cents), COUNT(*) "
		"FROM transactions t JOIN accounts a ON a.id = t.account_id "
		"WHERE substr(t.date,1,7) = ? "
		"GROUP BY a.name ORDER BY a.name;";
	if (sqlite3_prepare_v2(db, sql_acct, -1, &stmt, NULL) != SQLITE_OK) return 1;
	db_bind_text(stmt, 1, month);
	printf("By account:\n");
	printf("  %-20s  %12s  %6s\n", "ACCOUNT", "NET", "COUNT");
	printf("  --------------------  ------------  ------\n");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		char amt[32];
		util_format_amount(sqlite3_column_int64(stmt, 1), amt, sizeof amt);
		printf("  %-20.20s  %12s  %6lld\n",
		       sqlite3_column_text(stmt, 0),
		       amt,
		       (long long)sqlite3_column_int64(stmt, 2));
	}
	sqlite3_finalize(stmt);
	printf("\n");

	char details[64];
	snprintf(details, sizeof details, "month=%s tx=%lld", month, count);
	db_audit(db, "report.month", details);
	return 0;
}

int cmd_report(sqlite3 *db, int argc, char **argv)
{
	if (argc < 2 || strcmp(argv[0], "month") != 0) {
		fprintf(stderr, "usage: treasury report month <YYYY-MM>\n");
		return 2;
	}
	return report_month(db, argv[1]);
}
