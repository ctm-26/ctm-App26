#include "category.h"

#include <stdio.h>
#include <string.h>

#include "db.h"

long long category_find_id(sqlite3 *db, const char *name)
{
	sqlite3_stmt *stmt = NULL;
	const char *sql = "SELECT id FROM categories WHERE name = ? COLLATE NOCASE;";
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return -1;
	db_bind_text(stmt, 1, name);
	long long id = -1;
	if (sqlite3_step(stmt) == SQLITE_ROW) id = sqlite3_column_int64(stmt, 0);
	sqlite3_finalize(stmt);
	return id;
}

long long category_get_or_create(sqlite3 *db, const char *name)
{
	long long id = category_find_id(db, name);
	if (id > 0) return id;
	const char *sql = "INSERT INTO categories(name) VALUES(?);";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return -1;
	db_bind_text(stmt, 1, name);
	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	if (rc != SQLITE_DONE) return -1;
	return sqlite3_last_insert_rowid(db);
}

static int category_add(sqlite3 *db, const char *name)
{
	if (category_find_id(db, name) > 0) {
		printf("category exists: %s\n", name);
		return 0;
	}
	long long id = category_get_or_create(db, name);
	if (id < 0) {
		fprintf(stderr, "treasury: could not add category '%s'\n", name);
		return 1;
	}
	char details[256];
	snprintf(details, sizeof details, "name=%s id=%lld", name, id);
	db_audit(db, "category.add", details);
	printf("added category: %s\n", name);
	return 0;
}

static int category_list(sqlite3 *db)
{
	const char *sql =
		"SELECT c.id, c.name, "
		"  COALESCE((SELECT COUNT(*) FROM transactions t WHERE t.category_id = c.id), 0) "
		"FROM categories c ORDER BY c.name;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	printf("%-4s  %-24s  %s\n", "ID", "NAME", "TX");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		printf("%-4lld  %-24s  %lld\n",
		       (long long)sqlite3_column_int64(stmt, 0),
		       sqlite3_column_text(stmt, 1),
		       (long long)sqlite3_column_int64(stmt, 2));
	}
	sqlite3_finalize(stmt);
	return 0;
}

int cmd_category(sqlite3 *db, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr, "usage: treasury category <add|list> ...\n");
		return 2;
	}
	if (strcmp(argv[0], "add") == 0) {
		if (argc < 2) {
			fprintf(stderr, "usage: treasury category add <name>\n");
			return 2;
		}
		return category_add(db, argv[1]);
	}
	if (strcmp(argv[0], "list") == 0) {
		return category_list(db);
	}
	fprintf(stderr, "treasury: unknown category subcommand '%s'\n", argv[0]);
	return 2;
}
