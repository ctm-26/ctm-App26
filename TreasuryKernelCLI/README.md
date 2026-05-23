# Treasury Kernel v0.1

Treasury Kernel is a local-first C + SQLite personal finance ledger that imports
bank statements, categorizes transactions with deterministic rules, and produces
auditable monthly reports.

> Future roadmap: document vault, credit-report tracker, AI assistant layer,
> paper-trading risk lab. The roadmap is allowed to dream. **v0.1 is not allowed
> to wander.**

---

## The paper map (the whole creature)

```
                 TREASURY KERNEL v0.1
┌────────────────────────────────────────────────────────┐
│                    REAL WORLD INPUTS                   │
│                                                        │
│  Bank CSVs     Manual account entries     Rules file   │
└───────────────────────────┬────────────────────────────┘
                            │
                            v
┌────────────────────────────────────────────────────────┐
│                      IMPORT GATE                       │
│                                                        │
│  Parse CSV                                              │
│  Normalize date / description / amount                  │
│  Reject bad rows                                        │
│  Detect duplicates                                      │
└───────────────────────────┬────────────────────────────┘
                            │
                            v
┌────────────────────────────────────────────────────────┐
│                      LEDGER CORE                       │
│                                                        │
│  accounts                                               │
│  transactions                                           │
│  categories                                             │
│  import_batches                                         │
│  audit_log                                              │
└───────────────────────────┬────────────────────────────┘
                            │
                            v
┌────────────────────────────────────────────────────────┐
│                      RULE ENGINE                       │
│                                                        │
│  Match text patterns                                    │
│  Assign categories                                      │
│  Flag unknowns                                          │
│  Never guess silently                                   │
└───────────────────────────┬────────────────────────────┘
                            │
                            v
┌────────────────────────────────────────────────────────┐
│                     OUTPUT MIRROR                      │
│                                                        │
│  Monthly spending report                                │
│  Category totals                                        │
│  Account transaction list                               │
│  Audit trail                                            │
└────────────────────────────────────────────────────────┘
OUTSIDE v0.1:
┌────────────────────────────────────────────────────────┐
│                  FUTURE TRADING LAB                    │
│                                                        │
│  Paper trading only                                    │
│  Risk rules                                             │
│  No live money until budget system works                │
└────────────────────────────────────────────────────────┘
```

## Decisions (locked for v0.1)

| Decision      | v0.1                                                 |
| ------------- | ---------------------------------------------------- |
| Ledger model  | Single-entry. Double-entry later.                    |
| Language      | C core + SQLite + CLI.                               |
| Trading       | Roadmap only. Not in v0.1.                           |
| Storage       | One SQLite file. Local. Path from `$TREASURY_DB`.    |
| Source of truth | The audit log. Every command writes to it.        |

## Every feature fits inside one command

| Command                  | Box of the map                |
| ------------------------ | ----------------------------- |
| `treasury init`          | Ledger Core                   |
| `treasury account add`   | Ledger Core                   |
| `treasury import`        | Import Gate                   |
| `treasury tx list`       | Ledger Core / Output Mirror   |
| `treasury category add`  | Rule Engine                   |
| `treasury rule add`      | Rule Engine                   |
| `treasury classify`      | Rule Engine                   |
| `treasury report month`  | Output Mirror                 |
| `treasury audit`         | Audit Trail                   |
| `treasury export tx`     | Output Mirror (CSV)           |
| `treasury export audit`  | Audit Trail (CSV)             |

Every command writes to the audit log. When something looks wrong, the audit log
is the first thing to read.

## Build and test

```bash
cd TreasuryKernelCLI
make            # builds ./treasury
make test       # runs end-to-end CLI tests
make debug      # rebuilds with ASan + UBSan
```

Requires `libsqlite3-dev` and a C11 compiler.

## A complete walkthrough

```bash
# 1. create the database
export TREASURY_DB=./mybudget.db
./treasury init

# 2. add accounts
./treasury account add "Chase Checking" checking
./treasury account add "Amex Card"      credit

# 3. import a statement (auto-detects headers; supports Amount or Debit/Credit)
./treasury import statements/chase_may.csv --account "Chase Checking"

# 4. inspect what landed
./treasury tx list --month 2026-05 --limit 20

# 5. teach it your patterns
./treasury rule add SHOPRITE groceries 10
./treasury rule add SHELL    gas       10
./treasury rule add NETFLIX  subscriptions 10
./treasury rule add PAYROLL  income     5

# 6. apply rules. lowest priority number wins; case-insensitive substring match.
./treasury classify

# 7. read the mirror
./treasury report month 2026-05

# 8. read the history
./treasury audit --limit 50
```

### Exporting to CSV

Both the ledger and the audit log can be exported as RFC 4180-compliant CSV.
Fields that contain commas, quotes, or newlines are quoted and embedded quotes
are escaped by doubling. The default output is `stdout`; pass `--out` to write
to a file.

```bash
# all transactions, every account, every month
./treasury export tx --out tx.csv

# scoped slice (filters mirror `tx list`)
./treasury export tx --account "Chase Checking" --month 2026-05 --out chase_may.csv

# audit log in chronological order (oldest first); --limit caps the row count
./treasury export audit --out audit.csv
./treasury export audit --limit 100 > recent_audit.csv
```

Each export call appends its own row to the audit log (`export.tx` /
`export.audit`) so the trail of exports is itself traceable.

## CSV formats supported

The importer auto-detects column headers (case-insensitive). It needs:

* a **date** column: `date`, `transaction date`, `posting date`, `post date`, `trans date`
* a **description** column: `description`, `name`, `memo`, `payee`, `details`
* either a single **amount** column (signed), OR a pair of **debit** / **credit** columns
  (debit reduces balance, credit increases)

Amounts may include `$`, commas, parentheses for negatives. Dates may be
`YYYY-MM-DD`, `YYYY/MM/DD`, or `MM/DD/YYYY`. Two-digit years 00-69 expand to
20xx; 70-99 expand to 19xx.

## Duplicate detection

A transaction's identity is the tuple `(account, date, description, amount)`.
Re-importing the same CSV adds no rows; the importer reports how many were
skipped. There is no clever fuzzy match — that is a deliberate v0.1 choice. The
audit log records every batch so any false dedupe is traceable.

## Database schema (the six tables on the paper)

```
accounts(id, name UNIQUE, type, created_at)
categories(id, name UNIQUE NOCASE)
category_rules(id, pattern, category_id, priority, created_at)
import_batches(id, filename, account_id, imported_at, row_count, status)
transactions(id, account_id, date, description, amount_cents,
             category_id, import_batch_id, created_at,
             UNIQUE(account_id, date, description, amount_cents))
audit_log(id, action, details, created_at)
```

Money is stored as integer cents. Dates are ISO `YYYY-MM-DD` text.

## What v0.1 deliberately does not do

* No PDF parsing
* No AI / LLM classification
* No web dashboard
* No exchange APIs, brokerage integrations, or live trading
* No double-entry accounting
* No multi-currency
* No fuzzy duplicate detection
* No regex rules (substring only — by design, to keep behavior obvious)

Each of those is in the roadmap. None of them are in v0.1.
