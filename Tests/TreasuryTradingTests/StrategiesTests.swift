import XCTest
@testable import TreasuryTrading
import TreasuryKernel

final class StrategiesTests: XCTestCase {

    /// Synthetic price path with a clear regime change so the SMA crossover
    /// produces at least one buy then one sell.
    func syntheticCandles(_ n: Int = 200) -> [Candle] {
        var out: [Candle] = []
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<n {
            let trend = i < n / 2 ? Double(i) * 0.5 : Double(n - i) * 0.5
            let price = 100.0 + trend
            out.append(Candle(time: start.addingTimeInterval(TimeInterval(i * 3600)),
                              open: price, high: price + 0.5, low: price - 0.5,
                              close: price, volume: 1))
        }
        return out
    }

    func testIndicators() {
        let closes: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let sma = Indicators.sma(closes, period: 3)
        XCTAssertEqual(sma[2], 2.0)
        XCTAssertEqual(sma[9], 9.0)
        let rsi = Indicators.rsi(closes, period: 5)
        XCTAssertEqual(rsi.last??.rounded() ?? 0, 100, accuracy: 1)
    }

    func testBacktestRuns() {
        let strategy = SMACrossoverStrategy(fast: 10, slow: 20)
        let bt = Backtester(strategy: strategy, symbol: "TEST",
                            initialCashCents: 1_000_000)
        let r = bt.run(candles: syntheticCandles())
        XCTAssertFalse(r.equityCurve.isEmpty)
        XCTAssertEqual(r.stats.initialEquity.cents, 1_000_000)
    }

    func testRiskGovernorTrips() {
        let g = RiskGovernor(config: .init(
            maxPositionPctEquity: 0.5, maxOpenPositions: 5,
            maxDrawdownPct: 0.10, dailyLossLimitCents: 0,
            minCashReserveCents: 0))
        g.updateEquity(100_000)
        g.updateEquity(110_000)
        g.updateEquity(95_000)   // 13.6% drawdown -> trip
        XCTAssertTrue(g.tripped)
    }

    func testGovernorRejectsWhenNoPosition() {
        let g = RiskGovernor(config: .balanced)
        let order = Order(symbol: "BTC-USD", side: .sell, qty: 1)
        let snap = PaperBroker.Snapshot(
            cashCents: 10_000_00, equityCents: 10_000_00, positions: [])
        if case .reject = g.evaluate(order: order, lastPrice: 60_000, portfolio: snap) {
            // expected
        } else {
            XCTFail("expected reject")
        }
    }
}
