#ifndef TREASURY_TX_H
#define TREASURY_TX_H

#include <sqlite3.h>

int cmd_tx(sqlite3 *db, int argc, char **argv);

#endif
