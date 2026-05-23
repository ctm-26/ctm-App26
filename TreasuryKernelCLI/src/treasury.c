/*
 * Treasury Kernel v0.1
 *
 * Local-first C + SQLite personal finance ledger.
 *
 *   REAL WORLD  ->  IMPORT GATE  ->  LEDGER CORE  ->  RULE ENGINE  ->  OUTPUT MIRROR
 *      CSVs           parser           sqlite          patterns         reports
 *
 * Every command writes to the audit log; that is the spine.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sqlite3.h>

#include "account.h"
#include "audit.h"
#include "category.h"
#include "db.h"
#include "import.h"
#include "report.h"
#include "rule.h"
#include "tx.h"

#define TREASURY_VERSION "0.1.0"

static void print_usage(void)
{
	fputs(
		"Treasury Kernel v" TREASURY_VERSION "\n"
		"  local-first ledger: CSVs -> SQLite -> deterministic reports\n"
		"\n"
		"usage: treasury <command> [args]\n"
		"\n"
		"commands:\n"
		"  init                                  create / migrate the database\n"
		"  account add <name> <type>             add an account\n"
		"  account list                          list accounts\n"
		"  import <file.csv> --account <name>    parse CSV into ledger\n"
		"          [--dry-run]\n"
		"  tx list [--account N] [--month YYYY-MM] [--category C] [--limit N]\n"
		"  category add <name>                   add a category\n"
		"  category list                         list categories\n"
		"  rule add <pattern> <category> [pri]   add a text-match rule\n"
		"  rule list                             list rules in priority order\n"
		"  rule remove <id>                      remove a rule\n"
		"  classify                              apply rules to uncategorized tx\n"
		"  report month <YYYY-MM>                monthly category / account report\n"
		"  audit [--limit N]                     show audit log (newest first)\n"
		"  version                               print version\n"
		"\n"
		"database location: $TREASURY_DB or ./treasury.db\n",
		stderr);
}

static int cmd_init(sqlite3 *db)
{
	/* db_open already ran the schema migrations. */
	db_audit(db, "init", "schema applied");
	printf("treasury: initialized %s\n", db_default_path());
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) { print_usage(); return 2; }

	const char *cmd = argv[1];
	if (strcmp(cmd, "version") == 0 || strcmp(cmd, "--version") == 0) {
		printf("treasury %s\n", TREASURY_VERSION);
		return 0;
	}
	if (strcmp(cmd, "help") == 0 || strcmp(cmd, "-h") == 0 ||
	    strcmp(cmd, "--help") == 0) {
		print_usage();
		return 0;
	}

	sqlite3 *db = NULL;
	if (db_open(&db) != 0) {
		if (db) sqlite3_close(db);
		return 1;
	}

	int rc = 0;
	if (strcmp(cmd, "init") == 0)            rc = cmd_init(db);
	else if (strcmp(cmd, "account") == 0)    rc = cmd_account(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "category") == 0)   rc = cmd_category(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "rule") == 0)       rc = cmd_rule(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "import") == 0)     rc = cmd_import(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "tx") == 0)         rc = cmd_tx(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "classify") == 0)   rc = cmd_classify(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "report") == 0)     rc = cmd_report(db, argc - 2, argv + 2);
	else if (strcmp(cmd, "audit") == 0)      rc = cmd_audit(db, argc - 2, argv + 2);
	else {
		fprintf(stderr, "treasury: unknown command '%s'\n", cmd);
		print_usage();
		rc = 2;
	}

	sqlite3_close(db);
	return rc;
}
