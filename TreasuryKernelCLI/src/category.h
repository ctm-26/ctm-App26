#ifndef TREASURY_CATEGORY_H
#define TREASURY_CATEGORY_H

#include <sqlite3.h>

/* Find a category id by name (NOCASE). Returns -1 if not found. */
long long category_find_id(sqlite3 *db, const char *name);

/* Insert if missing, return id. Returns -1 on error. */
long long category_get_or_create(sqlite3 *db, const char *name);

int cmd_category(sqlite3 *db, int argc, char **argv);

#endif
