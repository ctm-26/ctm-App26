# ctm-App26

Treasury Kernel — a local-first personal finance ledger with a paper-trading
sandbox. Two clients on top of one SQLite schema:

| Client | Lives in | Status |
|---|---|---|
| C CLI (`treasury …`) | `TreasuryKernel/` | shipped (v0.1) |
| SwiftUI iPad app | `TreasuryiPad/` + `Sources/` | this commit (v0.2) |

The iPad app does not replace the CLI; both can open the same `treasury.db`.

```
REAL INPUTS  →  IMPORT GATE  →  LEDGER CORE  →  RULE ENGINE  →  OUTPUT MIRROR
                                                                      │
                                                                      └──→  FUTURE LAB (paper trading)
```

## What's in this repo

```
TreasuryKernel/           v0.1 — C + SQLite CLI (the canonical kernel)
Sources/
  TreasuryKernel/         Swift wrapper over the same SQLite schema
  TreasuryTrading/        strategies, paper broker, risk governor, price feed
  TreasuryUI/             SwiftUI iPad views + Swift Charts
TreasuryiPad/             the iPad app target (XcodeGen spec)
Tests/                    XCTest for the Swift modules
SocialMemoryVault/        unrelated companion iOS project
```

## Building

### CLI (any Unix with `libsqlite3-dev`)

```bash
cd TreasuryKernel
make            # builds ./treasury
make test       # 28-assertion end-to-end check
```

### iPad app (macOS with Xcode 15+)

```bash
brew install xcodegen   # one-time
cd TreasuryiPad
xcodegen generate
open TreasuryiPad.xcodeproj
```

### Swift modules (any platform with Swift)

```bash
swift build
swift test
```

See `TreasuryiPad/README.md` for the iPad app deep dive and `TreasuryKernel/README.md`
for the CLI walkthrough.

## What v0.2 adds on top of v0.1

| Layer | New |
|---|---|
| Schema | Three trading-lab tables (`paper_portfolios`, `paper_trades`, `paper_equity_points`) |
| Swift kernel | Same operations as the C kernel, exposed as `LedgerService` / `RuleService` / `ImportService` / `ReportService` / `AuditService` |
| Trading | `Backtester`, `PaperBroker`, `RiskGovernor`, `TradingEngine`, four named strategies, Coinbase public price feed |
| UI | iPad-first `NavigationSplitView` with Dashboard, Accounts, Transactions, Rules, Reports, Trading Lab, Audit. Swift Charts everywhere with a consistent mode-switcher pattern |

## What's still parked outside the wall

* No exchange API keys. No live orders. Paper-only.
* No claim of profitability. The four built-in strategies (`SMACrossover`,
  `RSIReversion`, `DonchianBreakout`, `DCA`) are deterministic starting points
  competing against a DCA baseline.
* No PDF parsing, no LLM categorization, no multi-currency.
