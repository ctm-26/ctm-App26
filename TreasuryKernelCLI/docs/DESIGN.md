# Treasury Kernel v0.1 — design notes

## One-line definition

Treasury Kernel is a local-first C + SQLite personal finance ledger that imports
bank statements, categorizes transactions with deterministic rules, and produces
auditable monthly reports.

## Five rules of v0.1

1. **Every feature fits inside one command.**
2. **Every command touches one box of the diagram.**
3. **Every command writes to the audit log.**
4. **No silent guessing.** Anything the rule engine cannot classify is left as
   `unknown`. The report prints `(unknown)` as a category line so it is
   visible, not hidden.
5. **No moving parts that are not v0.1.** No PDF parsing, no AI, no live
   trading, no web UI.

## Layering

```
treasury.c           dispatch
  account.c          ledger core / accounts
  category.c         rule engine / categories
  rule.c             rule engine / rules + classify
  import.c           import gate
  tx.c               ledger core / queries
  report.c           output mirror
  audit.c            audit trail
csv.c                generic RFC 4180-ish CSV reader
util.c               amount/date parsing, string helpers
db.c                 sqlite open + schema migrations + db_audit()
```

`treasury.c` only routes. Each command lives in one `cmd_*` function and writes
exactly one audit entry on success.

## Money

Stored as `INTEGER` cents. There is no floating point in the ledger path.
`util_parse_amount` accepts `$`, `,`, parentheses-for-negative, and signed
input; everything funnels through the same routine on both the single-amount
and debit/credit CSV paths.

## Dates

Stored as ISO `YYYY-MM-DD` text. The importer normalizes
`MM/DD/YYYY`, `M/D/YY`, `YYYY/MM/DD`, `YYYY-MM-DD` on the way in. Two-digit
years use the standard 00-69 → 2000-2069 / 70-99 → 1970-1999 window.

## Duplicate detection

`UNIQUE(account_id, date, description, amount_cents)` on the `transactions`
table. The importer uses `INSERT OR IGNORE`, so re-importing the same statement
is a no-op. The import batch row records every attempt (`row_count`,
`status`) and the audit log records the totals, so a duplicate sweep is fully
traceable.

This is intentionally strict; it makes false-positive dedupes possible (two
identical legitimate purchases on the same day for the same amount), and that
is acceptable for v0.1. The remedy is manual: edit the description on one of
the rows in the source CSV before re-importing, or insert a manual entry once
that command exists. The decision is recorded here so the next version can
revisit it deliberately.

## Rule engine

Matching is **case-insensitive substring** on the description. Order of
evaluation is `priority ASC, id ASC`; the first match wins. There is no regex,
no chaining, no Bayesian anything. The classifier only touches transactions
where `category_id IS NULL`, so it is safe to re-run. Unmatched transactions
stay `NULL` and the report shows them as `(unknown)` — visible, not silent.

## Audit log

`audit_log(id, action, details, created_at)`. Every state-changing command
writes one row. Actions used in v0.1:

```
init
account.add
category.add
rule.add
rule.remove
import
classify
report.month
```

`details` is human-readable free text — key=value pairs. v0.1 is local-only, so
this is a journal, not an integrity proof. v0.2 may add a hash chain.

## What this design does not solve yet

* No transfers between accounts (would distort net totals if you have multiple
  accounts and pay one from the other).
* No manual transaction entry command (only CSV import).
* No splits (a single transaction spanning multiple categories).
* No correction history — once a transaction is classified, re-running
  `classify` will not re-classify it; you must update categories manually via
  SQL or via a future `tx recategorize` command.

These are intentional v0.1 omissions, parked outside the wall.
