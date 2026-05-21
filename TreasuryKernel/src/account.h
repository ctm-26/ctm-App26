#ifndef TREASURY_ACCOUNT_H
#define TREASURY_ACCOUNT_H

#include <sqlite3.h>

/* Resolve an account name to its id. Returns -1 if not found. */
long long account_find_id(sqlite3 *db, const char *name);

int cmd_account(sqlite3 *db, int argc, char **argv);

#endif
