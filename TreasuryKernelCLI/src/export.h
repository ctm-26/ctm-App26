#ifndef TREASURY_EXPORT_H
#define TREASURY_EXPORT_H

#include <sqlite3.h>

int cmd_export(sqlite3 *db, int argc, char **argv);

#endif
