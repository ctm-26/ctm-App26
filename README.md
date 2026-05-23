[![ci: c-kernel](https://github.com/ctm-26/ctm-App26/actions/workflows/c-kernel.yml/badge.svg?branch=main)](https://github.com/ctm-26/ctm-App26/actions/workflows/c-kernel.yml)
[![ci: swift-tests](https://github.com/ctm-26/ctm-App26/actions/workflows/swift-tests.yml/badge.svg?branch=main)](https://github.com/ctm-26/ctm-App26/actions/workflows/swift-tests.yml)
[![ci: schema-parity](https://github.com/ctm-26/ctm-App26/actions/workflows/schema-parity.yml/badge.svg)](https://github.com/ctm-26/ctm-App26/actions/workflows/schema-parity.yml)

# ctm-App26

Treasury Kernel — a local-first personal finance ledger with a paper-trading
sandbox. Two clients sit on top of one SQLite schema; both can open the same
`treasury.db`.

| Client | Lives in | Role |
|---|---|---|
| C CLI (`treasury …`) | `TreasuryKernelCLI/` | canonical kernel, scriptable |
| SwiftUI iPad app | `TreasuryiPad/` + `Sources/` | day-to-day driver + trading lab |

```
REAL INPUTS  →  IMPORT GATE  →  LEDGER CORE  →  RULE ENGINE  →  OUTPUT MIRROR
                                                                      │
                                                                      └──→  FUTURE LAB (paper trading)
```

## What's in this repo

```
TreasuryKernelCLI/        C + SQLite CLI (the canonical kernel)
Sources/
  TreasuryKernel/         Swift module — wrapper over the same SQLite schema
  TreasuryTrading/        strategies, paper broker, risk governor, price feed
  TreasuryUI/             SwiftUI iPad views + Swift Charts (UIKit-gated)
TreasuryiPad/             the iPad app target (XcodeGen spec)
Tests/
  TreasuryKernelTests/    XCTest — ledger, rules, imports, audit
  TreasuryTradingTests/   XCTest — backtester, broker, governor, price feed
.github/workflows/        c-kernel · swift-tests · schema-parity
```

`TreasuryUI` is wrapped in `#if canImport(UIKit)`, so the macOS slice of the SPM
package builds and tests cleanly without dragging in the iPad UI.

## Building

### C CLI (any Unix with `libsqlite3-dev`)

```bash
cd TreasuryKernelCLI
make            # builds ./treasury
make test       # end-to-end assertion suite
```

### iPad app (macOS with Xcode 15+)

```bash
brew install xcodegen   # one-time
cd TreasuryiPad
xcodegen generate
open TreasuryiPad.xcodeproj
```

### Swift modules (any platform with Swift 5.9+)

```bash
swift build
swift test
```

See `TreasuryiPad/README.md` for the iPad app deep dive and
`TreasuryKernelCLI/README.md` for the CLI walkthrough.

## What v0.2.x adds

### Trading lab

- `Backtester` now uses a **unit-FIFO win-rate**, fee-correct average cost, and
  **granularity-aware Sharpe annualization** (per-bar interval drives the
  annualization factor).
- `RiskGovernor.Decision` carries a clamp note explaining any size reduction.
- `PaperBroker.execute` returns an explicit `ExecuteOutcome { filled | rejected }`,
  and the audit log distinguishes **broker rejects vs governor rejects**.
- `CoinbasePriceFeed` is fully testable via URLProtocol-based mocks (no live
  HTTP in tests).
- A **golden-data backtester regression fixture** — a 100-bar sine + drift
  series — locks the math against future regressions.

### iPad UX

- Loading / error / empty states across every view.
- Adaptive 4-card → 2×2 dashboard layout for compact width classes.
- Charts: **VoiceOver descriptors** + `chartXSelection` scrubbing on every
  time-series chart.
- iPad-first `NavigationSplitView` with the sidebar visible by default.
- **Pull-to-refresh** on every list view.
- `.sensoryFeedback` haptics on backtest run, import success, engine
  start/stop.
- Keyboard shortcuts: **Cmd+R** refresh dashboard, **Cmd+I** import,
  **Cmd+N** add (rules / accounts).
- `AppState.preferredCurrencyCode` drives locale-aware Money formatting at
  every high-traffic call site.
- `TransactionsView` supports in-line recategorize via context menu **and**
  swipe action.
- `AuditView` has an action filter, full-text search, and cursor pagination.

### Ledger reliability

- Null-safe SQLite text reads via `LedgerDatabase.text(_:default:)` and
  `optionalText(_:_:)` — no more crashes on legacy NULL columns.
- Manual transaction entry through `LedgerService.addTransaction(...)` with
  built-in deduplication.
- The `TreasuryUI` module compiles under `#if canImport(UIKit)` so the macOS
  slice of the SPM package (and its tests) builds without UIKit.

### CI

Three pinned workflows, all on `actions/checkout@v5` (Node 24) and
`actions/cache@v4`:

| Workflow | Runner | What it covers |
|---|---|---|
| `ci: c-kernel` | Linux | builds `treasury`, runs ASan + UBSan suite |
| `ci: swift-tests` | macOS 14 | `swift test` on Swift 5.9 |
| `ci: schema-parity` | PR-only | diffs the C and Swift schema definitions |

### Repo layout

- The C CLI moved from `TreasuryKernel/` to **`TreasuryKernelCLI/`** to
  disambiguate from the Swift module `Sources/TreasuryKernel/`.
- `SocialMemoryVault/` was removed from the tree; history is preserved in
  `main`.

## Still parked outside the wall

- **No exchange API keys. No live orders.** Paper-only, always.
- **No claim of profitability.** The four built-in strategies (`SMACrossover`,
  `RSIReversion`, `DonchianBreakout`, `DCA`) are deterministic starting points
  benchmarked against a DCA baseline.
- **No PDF parsing, no LLM categorization, no multi-currency.** The import
  gate is CSV-only; categorization is rule-based; Money is single-currency
  with a user-selected display code.
