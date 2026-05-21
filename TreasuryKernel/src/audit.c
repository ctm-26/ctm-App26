#include "audit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "db.h"

int cmd_audit(sqlite3 *db, int argc, char **argv)
{
	int limit = 50;
	for (int i = 0; i < argc; i++) {
		if (strcmp(argv[i], "--limit") == 0 && i + 1 < argc) {
			limit = atoi(argv[++i]);
			if (limit <= 0) limit = 50;
		} else {
			fprintf(stderr, "treasury: unknown audit flag: %s\n", argv[i]);
			return 2;
		}
	}
	const char *sql =
		"SELECT id, created_at, action, COALESCE(details, '') "
		"FROM audit_log ORDER BY id DESC LIMIT ?;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	sqlite3_bind_int(stmt, 1, limit);
	printf("%-5s  %-20s  %-18s  %s\n", "ID", "WHEN (UTC)", "ACTION", "DETAILS");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		printf("%-5lld  %-20s  %-18s  %s\n",
		       (long long)sqlite3_column_int64(stmt, 0),
		       sqlite3_column_text(stmt, 1),
		       sqlite3_column_text(stmt, 2),
		       sqlite3_column_text(stmt, 3));
	}
	sqlite3_finalize(stmt);
	return 0;
}
