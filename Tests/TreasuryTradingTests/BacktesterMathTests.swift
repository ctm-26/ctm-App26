import XCTest
@testable import TreasuryTrading
import TreasuryKernel

final class BacktesterMathTests: XCTestCase {

    /// 10 flat bars at $100. Lets us assert structural properties of the
    /// equity curve and cost basis without strategy noise.
    private func flatCandles(_ n: Int = 10, price: Double = 100.0) -> [Candle] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<n).map { i in
            Candle(time: start.addingTimeInterval(TimeInterval(i * 3600)),
                   open: price, high: price, low: price,
                   close: price, volume: 1)
        }
    }

    /// 10 monotonically rising bars. DCA at intervalBars=2 fires at bars 2,4,6,8
    /// = 4 buys, no sells, so we can read cost basis directly.
    private func risingCandles(_ n: Int = 10) -> [Candle] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<n).map { i in
            let p = 100.0 + Double(i)
            return Candle(time: start.addingTimeInterval(TimeInterval(i * 3600)),
                          open: p, high: p, low: p, close: p, volume: 1)
        }
    }

    // D1(a): equityCurve.count == candles.count — the post-loop duplicate
    // sample was removed.
    func testEquityCurveHasOneSamplePerBar() {
        let strategy = DCAStrategy(intervalBars: 5, cashPerBuyCents: 1_000)
        let bt = Backtester(strategy: strategy, symbol: "TEST",
                            initialCashCents: 100_000, feeRate: 0)
        let candles = flatCandles(10)
        let r = bt.run(candles: candles)
        XCTAssertEqual(r.equityCurve.count, candles.count,
                       "expected exactly one EquityPoint per candle (no duplicate final sample)")
    }

    // D1(b): Sharpe respects the barsPerYear annualization factor. Two
    // backtests over identical equity series should produce Sharpe values
    // whose ratio equals sqrt(bpy1 / bpy2).
    func testSharpeRespectsBarsPerYear() {
        let strategy = DCAStrategy(intervalBars: 2, cashPerBuyCents: 1_000)
        let candles = risingCandles(20)
        let btEquities = Backtester(
            strategy: strategy, symbol: "TEST",
            initialCashCents: 100_000, feeRate: 0, barsPerYear: 252)
        let btCryptoHourly = Backtester(
            strategy: strategy, symbol: "TEST",
            initialCashCents: 100_000, feeRate: 0,
            barsPerYear: Granularity.hour.barsPerYear)

        let s1 = btEquities.run(candles: candles).stats.sharpe
        let s2 = btCryptoHourly.run(candles: candles).stats.sharpe
        XCTAssertNotEqual(s1, 0, "expected non-zero Sharpe on a rising series")
        XCTAssertNotEqual(s2, 0, "expected non-zero Sharpe on a rising series")
        // ratio of sharpes should match sqrt(ratio of bpy)
        let expected = (Granularity.hour.barsPerYear / 252.0).squareRoot()
        XCTAssertEqual(s2 / s1, expected, accuracy: 1e-6,
                       "Sharpe ratio between two annualizations should equal sqrt(bpy ratio)")
    }

    // D1(c): total cost basis on the position includes fees, per the
    // "average-cost includes fees" convention. After exactly one DCA buy
    // with a non-zero fee, the reconstructed average cost per unit is
    // strictly greater than the mark price by the fee component.
    func testCostBasisIncludesFees() {
        // Interval=4 with 5 flat bars: DCA fires only at bar 4 (idx=4) since
        // bars 0 (idx=0 fails idx>0) and 1..3 fail idx%4==0.
        let strategy = DCAStrategy(intervalBars: 4, cashPerBuyCents: 1_000)
        let bt = Backtester(strategy: strategy, symbol: "TEST",
                            initialCashCents: 1_000_000, feeRate: 0.01,
                            governorConfig: .balanced)
        let candles = flatCandles(5, price: 100.0)
        let r = bt.run(candles: candles)
        XCTAssertEqual(r.trades.count, 1, "DCA should have fired exactly once at bar 4")
        guard let fill = r.trades.first else { return }
        XCTAssertEqual(fill.order.side, .buy)
        XCTAssertGreaterThan(fill.feeCents, 0,
                             "non-zero feeRate should produce non-zero feeCents")
        // Reconstruct what the broker's avgCost would have been: (notional +
        // fee) / qty in cents/unit. With fees included, this must exceed the
        // mark price; without fees (the bug we just fixed), it would equal it.
        let notionalCents = Double(fill.priceCents) * fill.filledQty
        let withFeesCents = notionalCents + Double(fill.feeCents)
        let expectedAvgCostPerUnit = withFeesCents / fill.filledQty
        let markCents = Double(fill.priceCents)
        XCTAssertGreaterThan(expectedAvgCostPerUnit, markCents,
                             "average-cost convention should include fees, so avg > mark")
    }
}
