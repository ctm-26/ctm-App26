#ifndef TREASURY_DB_H
#define TREASURY_DB_H

#include <sqlite3.h>

/* Resolve the database file path.
   Uses $TREASURY_DB if set, otherwise "./treasury.db". */
const char *db_default_path(void);

/* Open (or create) the database and run migrations. */
int db_open(sqlite3 **out_db);

/* Convenience: bind a non-null text value. */
int db_bind_text(sqlite3_stmt *stmt, int idx, const char *s);

/* Run a single statement, no params. Logs and returns non-zero on error. */
int db_exec(sqlite3 *db, const char *sql);

/* Append an audit entry. action must be non-NULL; details may be NULL. */
int db_audit(sqlite3 *db, const char *action, const char *details);

#endif
