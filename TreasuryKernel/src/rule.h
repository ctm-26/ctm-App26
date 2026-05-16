#ifndef TREASURY_RULE_H
#define TREASURY_RULE_H

#include <sqlite3.h>

int cmd_rule(sqlite3 *db, int argc, char **argv);

/* Apply rules to all currently uncategorized transactions.
   Writes counts into out_classified and out_remaining_unknown. */
int rule_classify_all(sqlite3 *db,
                      long long *out_classified,
                      long long *out_remaining_unknown);

int cmd_classify(sqlite3 *db, int argc, char **argv);

#endif
