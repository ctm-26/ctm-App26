#include "rule.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "category.h"
#include "db.h"
#include "util.h"

static int rule_add(sqlite3 *db, const char *pattern, const char *category,
                    int priority)
{
	long long cat_id = category_get_or_create(db, category);
	if (cat_id < 0) {
		fprintf(stderr, "treasury: could not resolve category '%s'\n", category);
		return 1;
	}
	const char *sql =
		"INSERT INTO category_rules(pattern, category_id, priority) VALUES(?, ?, ?);";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	db_bind_text(stmt, 1, pattern);
	sqlite3_bind_int64(stmt, 2, cat_id);
	sqlite3_bind_int(stmt, 3, priority);
	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	if (rc != SQLITE_DONE) {
		fprintf(stderr, "treasury: could not add rule: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	char details[512];
	snprintf(details, sizeof details, "pattern=\"%s\" category=%s priority=%d",
	         pattern, category, priority);
	db_audit(db, "rule.add", details);
	printf("added rule: \"%s\" -> %s (priority %d)\n",
	       pattern, category, priority);
	return 0;
}

static int rule_list(sqlite3 *db)
{
	const char *sql =
		"SELECT r.id, r.pattern, c.name, r.priority "
		"FROM category_rules r JOIN categories c ON c.id = r.category_id "
		"ORDER BY r.priority ASC, r.id ASC;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	printf("%-4s  %-30s  %-20s  %s\n", "ID", "PATTERN", "CATEGORY", "PRI");
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		printf("%-4lld  %-30s  %-20s  %d\n",
		       (long long)sqlite3_column_int64(stmt, 0),
		       sqlite3_column_text(stmt, 1),
		       sqlite3_column_text(stmt, 2),
		       sqlite3_column_int(stmt, 3));
	}
	sqlite3_finalize(stmt);
	return 0;
}

static int rule_remove(sqlite3 *db, long long id)
{
	const char *sql = "DELETE FROM category_rules WHERE id = ?;";
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
		fprintf(stderr, "treasury: prepare failed: %s\n", sqlite3_errmsg(db));
		return 1;
	}
	sqlite3_bind_int64(stmt, 1, id);
	int rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);
	if (rc != SQLITE_DONE) return 1;
	if (sqlite3_changes(db) == 0) {
		printf("no rule with id %lld\n", id);
		return 1;
	}
	char details[64];
	snprintf(details, sizeof details, "id=%lld", id);
	db_audit(db, "rule.remove", details);
	printf("removed rule %lld\n", id);
	return 0;
}

int cmd_rule(sqlite3 *db, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr, "usage: treasury rule <add|list|remove> ...\n");
		return 2;
	}
	if (strcmp(argv[0], "add") == 0) {
		if (argc < 3) {
			fprintf(stderr,
			        "usage: treasury rule add <pattern> <category> [priority]\n");
			return 2;
		}
		int priority = 100;
		if (argc >= 4) priority = atoi(argv[3]);
		return rule_add(db, argv[1], argv[2], priority);
	}
	if (strcmp(argv[0], "list") == 0) return rule_list(db);
	if (strcmp(argv[0], "remove") == 0) {
		if (argc < 2) {
			fprintf(stderr, "usage: treasury rule remove <id>\n");
			return 2;
		}
		return rule_remove(db, atoll(argv[1]));
	}
	fprintf(stderr, "treasury: unknown rule subcommand '%s'\n", argv[0]);
	return 2;
}

/* Apply rules: only touch transactions where category_id IS NULL.
   Deterministic order: lowest priority number wins; if priority equal, oldest id wins.
   Uses case-insensitive substring match on description. */
int rule_classify_all(sqlite3 *db,
                      long long *out_classified,
                      long long *out_remaining_unknown)
{
	if (out_classified) *out_classified = 0;
	if (out_remaining_unknown) *out_remaining_unknown = 0;

	/* Load rules into memory; tx counts may be large, rule count is small. */
	const char *rsql =
		"SELECT pattern, category_id FROM category_rules "
		"ORDER BY priority ASC, id ASC;";
	sqlite3_stmt *rstmt = NULL;
	if (sqlite3_prepare_v2(db, rsql, -1, &rstmt, NULL) != SQLITE_OK) return -1;

	typedef struct { char *pattern; long long category_id; } rule_t;
	rule_t *rules = NULL;
	size_t rule_count = 0, rule_cap = 0;
	while (sqlite3_step(rstmt) == SQLITE_ROW) {
		if (rule_count == rule_cap) {
			size_t nc = rule_cap ? rule_cap * 2 : 16;
			rule_t *nr = realloc(rules, nc * sizeof *rules);
			if (!nr) { sqlite3_finalize(rstmt); free(rules); return -1; }
			rules = nr; rule_cap = nc;
		}
		const unsigned char *p = sqlite3_column_text(rstmt, 0);
		rules[rule_count].pattern = util_xstrdup((const char *)p);
		rules[rule_count].category_id = sqlite3_column_int64(rstmt, 1);
		rule_count++;
	}
	sqlite3_finalize(rstmt);

	const char *tsql =
		"SELECT id, description FROM transactions "
		"WHERE category_id IS NULL ORDER BY id;";
	sqlite3_stmt *tstmt = NULL;
	if (sqlite3_prepare_v2(db, tsql, -1, &tstmt, NULL) != SQLITE_OK) {
		for (size_t i = 0; i < rule_count; i++) free(rules[i].pattern);
		free(rules);
		return -1;
	}

	const char *usql =
		"UPDATE transactions SET category_id = ? WHERE id = ?;";
	sqlite3_stmt *ustmt = NULL;
	if (sqlite3_prepare_v2(db, usql, -1, &ustmt, NULL) != SQLITE_OK) {
		sqlite3_finalize(tstmt);
		for (size_t i = 0; i < rule_count; i++) free(rules[i].pattern);
		free(rules);
		return -1;
	}

	db_exec(db, "BEGIN;");
	long long classified = 0, unknown = 0;
	while (sqlite3_step(tstmt) == SQLITE_ROW) {
		long long tid = sqlite3_column_int64(tstmt, 0);
		const char *desc = (const char *)sqlite3_column_text(tstmt, 1);
		long long match_cat = -1;
		for (size_t i = 0; i < rule_count; i++) {
			if (util_contains_ci(desc, rules[i].pattern)) {
				match_cat = rules[i].category_id;
				break;
			}
		}
		if (match_cat > 0) {
			sqlite3_bind_int64(ustmt, 1, match_cat);
			sqlite3_bind_int64(ustmt, 2, tid);
			if (sqlite3_step(ustmt) == SQLITE_DONE) classified++;
			sqlite3_reset(ustmt);
		} else {
			unknown++;
		}
	}
	db_exec(db, "COMMIT;");

	sqlite3_finalize(tstmt);
	sqlite3_finalize(ustmt);
	for (size_t i = 0; i < rule_count; i++) free(rules[i].pattern);
	free(rules);

	if (out_classified) *out_classified = classified;
	if (out_remaining_unknown) *out_remaining_unknown = unknown;
	return 0;
}

int cmd_classify(sqlite3 *db, int argc, char **argv)
{
	(void)argc; (void)argv;
	long long classified = 0, unknown = 0;
	if (rule_classify_all(db, &classified, &unknown) != 0) {
		fprintf(stderr, "treasury: classify failed\n");
		return 1;
	}
	printf("classified %lld transaction(s); %lld remain unknown\n",
	       classified, unknown);
	char details[128];
	snprintf(details, sizeof details, "classified=%lld unknown=%lld",
	         classified, unknown);
	db_audit(db, "classify", details);
	return 0;
}
