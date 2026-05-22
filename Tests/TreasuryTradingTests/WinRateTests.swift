import XCTest
@testable import TreasuryTrading
import TreasuryKernel

/// Verifies the backtester win-rate FIFO: 3 separate buy lots followed by one
/// large sell that crosses all three should split into a mix of wins/losses
/// counted by unit, not by trade.
final class WinRateTests: XCTestCase {

    /// A toy strategy that fires a predetermined sequence of actions on
    /// successive bars. Used to inject exact buy/sell shapes without dragging
    /// in a real indicator-driven strategy.
    struct ScriptedStrategy: Strategy {
        let script: [StrategyDecision]
        var name: String { "scripted" }
        var summary: String { "test fixture" }
        func warmupOK(_ ctx: StrategyContext) -> Bool { true }
        func decide(_ ctx: StrategyContext) -> StrategyDecision {
            let i = ctx.history.count - 1
            return i >= 0 && i < script.count ? script[i] : .hold
        }
    }

    // 3 buy lots at prices $100, $110, $90 (1 unit each), then a single sell
    // of all 3 units at $105. FIFO matches: 1 unit @100 (win, 105>100), 1 unit
    // @110 (loss, 105<110), 1 unit @90 (win, 105>90). Result: 2 wins, 1 loss
    // by unit — so winRate == 2/3, not 1/1 (which is what the old per-trade
    // stack would have reported: 1 sell trade matched against the most-recent
    // buy @90, scoring 1 win / 1 sell).
    func testFIFOSplitsLargeSellAcrossMultipleLots() {
        // Each candle close drives the price strategies and the broker mark.
        // Bars: prices 100, 110, 90, 105, 105 — three buys then a sell.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let prices: [Double] = [100, 110, 90, 105, 105]
        let candles = prices.enumerated().map { (i, p) in
            Candle(time: start.addingTimeInterval(TimeInterval(i * 3600)),
                   open: p, high: p, low: p, close: p, volume: 1)
        }
        let script: [StrategyDecision] = [
            .buy(qtyBaseUnits: 1.0, reason: "lot1"),
            .buy(qtyBaseUnits: 1.0, reason: "lot2"),
            .buy(qtyBaseUnits: 1.0, reason: "lot3"),
            .sell(qtyBaseUnits: 3.0, reason: "exit all"),
            .hold,
        ]
        let strategy = ScriptedStrategy(script: script)
        // Generous governor + no fee so we get exact fills.
        let bt = Backtester(
            strategy: strategy, symbol: "TEST",
            initialCashCents: 1_000_000_00, feeRate: 0,
            governorConfig: .init(maxPositionPctEquity: 1.0, maxOpenPositions: 5,
                                  maxDrawdownPct: 0.99, dailyLossLimitCents: 0,
                                  minCashReserveCents: 0))
        let r = bt.run(candles: candles)
        // 3 buys + 1 sell, by trade count.
        XCTAssertEqual(r.trades.count, 4)
        // 2 winning units, 1 losing unit ⇒ winRate = 2/3.
        XCTAssertEqual(r.stats.winRate, 2.0 / 3.0, accuracy: 1e-9,
                       "win-rate should be unit-weighted FIFO, not per-trade")
    }
}
