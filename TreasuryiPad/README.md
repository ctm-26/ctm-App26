# Treasury Kernel — iPad (v0.2)

iPad-first SwiftUI app on top of the same SQLite ledger the C CLI writes to.

> v0.1 (C CLI) shipped first as the source of truth: `REAL INPUTS → IMPORT GATE
> → LEDGER CORE → RULE ENGINE → OUTPUT MIRROR`. v0.2 wraps that organism in a
> touch interface and adds the **paper-trading lab** that was parked outside
> the wall.

## What this is, and what it isn't

| | v0.2 iPad |
|---|---|
| ✅ | Local-first SwiftUI iPad app (also runs on macOS via "Designed for iPad") |
| ✅ | Same SQLite schema as the C CLI — you can open one database with both tools |
| ✅ | Paper-trading sandbox with **live** Coinbase public price data |
| ✅ | Four named strategies, deterministic, in `TreasuryTrading` |
| ✅ | Risk governor with max drawdown, daily-loss kill switch, position-size caps |
| ✅ | Backtester + interactive Swift Charts for every box of the diagram |
| ❌ | No exchange API keys, no real orders, no live trading |
| ❌ | No claim that any strategy will make money — they're starting points |

## Layout

```
ctm-App26/
├── Package.swift                 ← SPM root for the Swift libraries
├── Sources/
│   ├── TreasuryKernel/           ← SQLite + ledger services (mirrors C kernel)
│   ├── TreasuryTrading/          ← strategies, backtester, paper broker, price feed
│   └── TreasuryUI/               ← SwiftUI views + Swift Charts
├── Tests/
│   ├── TreasuryKernelTests/      ← end-to-end ledger test
│   └── TreasuryTradingTests/     ← indicators, backtester, risk
├── TreasuryKernel/               ← the v0.1 C CLI (unchanged)
└── TreasuryiPad/
    ├── App/TreasuryiPadApp.swift ← @main entry, opens the ledger
    ├── Resources/Info.plist
    └── project.yml               ← XcodeGen spec
```

## Build the iPad app

You need Xcode 15+ on macOS. From the repo root:

```bash
brew install xcodegen        # one-time
cd TreasuryiPad
xcodegen generate            # produces TreasuryiPad.xcodeproj
open TreasuryiPad.xcodeproj
```

Then in Xcode: select an iPad simulator (or any iPad device) and hit Run.

Running on macOS works too — the project is set up for "iPad on Mac" via the
`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` flag.

> `TreasuryiPad.xcodeproj` is git-ignored and **must be regenerated** after
> every clone (or after any change to `project.yml`). Re-run `xcodegen
> generate` whenever a teammate edits the spec.

### Tests

The unit tests (`TreasuryKernelTests`, `TreasuryTradingTests`) live in the SPM
package, not in the Xcode project. Run them from the repo root:

```bash
swift test
```

This keeps the Xcode app target lean and matches CI, which runs `swift test`
on macOS and Linux. The `.xcodeproj` does not currently bundle an Xcode test
target.

## Verify the Swift core (no Xcode required)

```bash
swift build                  # builds the three libraries
swift test                   # runs TreasuryKernelTests + TreasuryTradingTests
```

This works on macOS or Linux (the trading and kernel modules are
Foundation-only).

## The chart-mode pattern

Every screen that shows a chart uses the same `ChartModeSwitcher` component.
The user picks the visual; the underlying data does not change. This keeps the
app modular as it grows — adding a new visual to an existing screen is a
single enum case and a single `BarMark`/`LineMark`/`SectorMark` branch.

| Screen | Modes |
|---|---|
| Dashboard → Spend lens | Donut · Bars · Stack |
| Dashboard → Timeline lens | Area · Line |
| Dashboard → Cashflow lens | Stacked bars |
| Trading Lab → Backtest | Equity / Drawdown / Both, plus Candles / Line / Area on the price chart |
| Trading Lab → Paper portfolio | Equity / Drawdown / Both |

## The trading lab in one paragraph

`StrategyEngine` drives a `Strategy` (one of `SMACrossoverStrategy`,
`RSIReversionStrategy`, `DonchianBreakoutStrategy`, `DCAStrategy`) on a stream
of candles from a `PriceFeed`. Decisions become `Order`s. Every order passes
through the `RiskGovernor` (max drawdown, max position % equity, max open
positions, daily-loss kill switch). Approved orders execute against the
`PaperBroker`, which holds cash and positions in memory and persists fills to
`paper_trades` plus equity samples to `paper_equity_points`. The backtester
runs the same loop over historical candles without touching the network. None
of this places a real order; there is no exchange auth in this build.

## Why these four strategies

| Strategy | Idea | What it's a baseline for |
|---|---|---|
| `SMACrossoverStrategy` | Fast / slow moving-average crossover | Trend following |
| `RSIReversionStrategy` | Buy oversold, exit on cover | Mean reversion |
| `DonchianBreakoutStrategy` | N-period high/low breakout | Range-breakout / Turtle-style |
| `DCAStrategy` | Buy a fixed dollar amount on schedule | The honest baseline |

I'm not selling these as profitable. DCA exists in the list specifically
because it's the strategy every active strategy is competing against. If a
new strategy can't beat DCA's curve on the backtester, it doesn't deserve
paper time either.

## How the two storage tools share one database

The C CLI and the iPad app both target `treasury.db` with the same schema.
`Schema.swift` documents the contract; `TreasuryKernel/src/db.c` is the C
side of the same contract. The iPad app adds three trading-lab tables
(`paper_portfolios`, `paper_trades`, `paper_equity_points`); the CLI ignores
them.

You can move a database file between the CLI and the iPad app freely. The
audit log is shared too — entries written by `treasury import` from the CLI
show up in the iPad Audit view.
