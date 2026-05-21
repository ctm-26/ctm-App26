#ifndef TREASURY_IMPORT_H
#define TREASURY_IMPORT_H

#include <sqlite3.h>

int cmd_import(sqlite3 *db, int argc, char **argv);

#endif
