#include "db.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *SCHEMA_SQL =
	"PRAGMA foreign_keys = ON;\n"
	"PRAGMA journal_mode = WAL;\n"
	"CREATE TABLE IF NOT EXISTS accounts ("
	"  id INTEGER PRIMARY KEY,"
	"  name TEXT NOT NULL UNIQUE,"
	"  type TEXT NOT NULL,"
	"  created_at TEXT NOT NULL DEFAULT (datetime('now'))"
	");\n"
	"CREATE TABLE IF NOT EXISTS categories ("
	"  id INTEGER PRIMARY KEY,"
	"  name TEXT NOT NULL UNIQUE COLLATE NOCASE"
	");\n"
	"CREATE TABLE IF NOT EXISTS category_rules ("
	"  id INTEGER PRIMARY KEY,"
	"  pattern TEXT NOT NULL,"
	"  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,"
	"  priority INTEGER NOT NULL DEFAULT 100,"
	"  created_at TEXT NOT NULL DEFAULT (datetime('now'))"
	");\n"
	"CREATE INDEX IF NOT EXISTS idx_rules_priority ON category_rules(priority);\n"
	"CREATE TABLE IF NOT EXISTS import_batches ("
	"  id INTEGER PRIMARY KEY,"
	"  filename TEXT NOT NULL,"
	"  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,"
	"  imported_at TEXT NOT NULL DEFAULT (datetime('now')),"
	"  row_count INTEGER NOT NULL,"
	"  status TEXT NOT NULL"
	");\n"
	"CREATE TABLE IF NOT EXISTS transactions ("
	"  id INTEGER PRIMARY KEY,"
	"  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,"
	"  date TEXT NOT NULL,"
	"  description TEXT NOT NULL,"
	"  amount_cents INTEGER NOT NULL,"
	"  category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,"
	"  import_batch_id INTEGER REFERENCES import_batches(id) ON DELETE SET NULL,"
	"  created_at TEXT NOT NULL DEFAULT (datetime('now')),"
	"  UNIQUE(account_id, date, description, amount_cents)"
	");\n"
	"CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);\n"
	"CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);\n"
	"CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);\n"
	"CREATE TABLE IF NOT EXISTS audit_log ("
	"  id INTEGER PRIMARY KEY,"
	"  action TEXT NOT NULL,"
	"  details TEXT,"
	"  created_at TEXT NOT NULL DEFAULT (datetime('now'))"
	");\n";

const char *db_default_path(void)
{
	const char *env = getenv("TREASURY_DB");
	if (env && *env) return env;
	return "treasury.db";
}

int db_exec(sqlite3 *db, const char *sql)
{
	char *errmsg = NULL;
	int rc = sqlite3_exec(db, sql, NULL, NULL, &errmsg);
	if (rc != SQLITE_OK) {
		fprintf(stderr, "treasury: sql error: %s\n", errmsg ? errmsg : "?");
		sqlite3_free(errmsg);
		return -1;
	}
	return 0;
}

int db_open(sqlite3 **out_db)
{
	const char *path = db_default_path();
	int rc = sqlite3_open(path, out_db);
	if (rc != SQLITE_OK) {
		fprintf(stderr, "treasury: cannot open %s: %s\n",
		        path, sqlite3_errmsg(*out_db));
		return -1;
	}
	if (db_exec(*out_db, SCHEMA_SQL) != 0) return -1;
	return 0;
}

int db_bind_text(sqlite3_stmt *stmt, int idx, const char *s)
{
	return sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT);
}

int db_audit(sqlite3 *db, const char *action, const char *details)
{
	const char *sql =
		"INSERT INTO audit_log(action, details) VALUES(?, ?);";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: audit prepare failed: %s\n",
		        sqlite3_errmsg(db));
		return -1;
	}
	db_bind_text(stmt, 1, action);
	if (details) db_bind_text(stmt, 2, details);
	else sqlite3_bind_null(stmt, 2);
	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	return rc == SQLITE_DONE ? 0 : -1;
}
