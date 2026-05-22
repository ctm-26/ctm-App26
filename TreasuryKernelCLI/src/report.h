#ifndef TREASURY_REPORT_H
#define TREASURY_REPORT_H

#include <sqlite3.h>

int cmd_report(sqlite3 *db, int argc, char **argv);

#endif
