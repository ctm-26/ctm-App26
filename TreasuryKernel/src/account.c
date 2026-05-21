#include "account.h"

#include <stdio.h>
#include <string.h>

#include "db.h"

long long account_find_id(sqlite3 *db, const char *name)
{
	sqlite3_stmt *stmt = NULL;
	const char *sql = "SELECT id FROM accounts WHERE name = ?;";
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return -1;
	db_bind_text(stmt, 1, name);
	long long id = -1;
	if (sqlite3_step(stmt) == SQLITE_ROW) id = sqlite3_column_int64(stmt, 0);
	sqlite3_finalize(stmt);
	return id;
}

static int account_add(sqlite3 *db, const char *name, const char *type)
{
	const char *sql =
		"INSERT INTO accounts(name, type) VALUES(?, ?);";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	db_bind_text(stmt, 1, name);
	db_bind_text(stmt, 2, type);
	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	if (rc != SQLITE_DONE) {
		fprintf(stderr, "treasury: could not add account '%s': %s\n",
		        name, sqlite3_errmsg(db));
		return 1;
	}

	char details[256];
	snprintf(details, sizeof details, "name=%s type=%s", name, type);
	db_audit(db, "account.add", details);
	printf("added account: %s (%s)\n", name, type);
	return 0;
}

static int account_list(sqlite3 *db)
{
	const char *sql =
		"SELECT a.id, a.name, a.type, a.created_at, "
		"  COALESCE((SELECT COUNT(*) FROM transactions t WHERE t.account_id = a.id), 0) "
		"FROM accounts a ORDER BY a.name;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	printf("%-4s  %-24s  %-10s  %-20s  %s\n", "ID", "NAME", "TYPE", "CREATED", "TX");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		printf("%-4lld  %-24s  %-10s  %-20s  %lld\n",
		       (long long)sqlite3_column_int64(stmt, 0),
		       sqlite3_column_text(stmt, 1),
		       sqlite3_column_text(stmt, 2),
		       sqlite3_column_text(stmt, 3),
		       (long long)sqlite3_column_int64(stmt, 4));
	}
	sqlite3_finalize(stmt);
	return 0;
}

int cmd_account(sqlite3 *db, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr, "usage: treasury account <add|list> ...\n");
		return 2;
	}
	if (strcmp(argv[0], "add") == 0) {
		if (argc < 3) {
			fprintf(stderr,
			        "usage: treasury account add <name> <type>\n"
			        "       type: checking | savings | credit | cash | brokerage | other\n");
			return 2;
		}
		return account_add(db, argv[1], argv[2]);
	}
	if (strcmp(argv[0], "list") == 0) {
		return account_list(db);
	}
	fprintf(stderr, "treasury: unknown account subcommand '%s'\n", argv[0]);
	return 2;
}
