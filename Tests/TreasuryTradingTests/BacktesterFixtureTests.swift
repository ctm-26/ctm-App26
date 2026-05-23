import XCTest
@testable import TreasuryTrading
import TreasuryKernel
import Foundation

/// Golden-data regression tests. We feed a fixed deterministic synthetic price
/// series through each public strategy and assert structural invariants on the
/// `BacktestResult`. If a refactor changes equity-curve length, win-rate
/// accounting, or Sharpe annualization, these tests fail loudly.
///
/// The fixture is generated programmatically (not loaded from disk) so the
/// data lives next to the assertions and can be re-derived by inspection.
final class BacktesterFixtureTests: XCTestCase {

    // MARK: - Fixture

    /// Origin used for every fixture timestamp. Static `Date(timeIntervalSince1970:)`
    /// — no wall clock, no random source — so test output is pure.
    static let fixtureStart = Date(timeIntervalSince1970: 1_700_000_000)

    /// Hourly spacing.
    static let fixtureSpacing: TimeInterval = 3600

    /// Number of bars in the fixture.
    static let fixtureBarCount = 100

    /// Closed-form price function. Exposed so individual tests can recompute
    /// expected values without hardcoding a magic number.
    static func fixturePrice(_ i: Int) -> Double {
        return 100.0 + 20.0 * sin(2.0 * .pi * Double(i) / 24.0) + 0.1 * Double(i)
    }

    /// Deterministic 100-bar synthetic series: a sine wave with linear trend
    /// so SMA / RSI / Donchian all get some signal, plus a known final price.
    /// Open == close == mid; high = mid+0.5; low = mid-0.5; volume = 1.
    static let fixtureCandles: [Candle] = {
        (0..<fixtureBarCount).map { i in
            let price = fixturePrice(i)
            return Candle(
                time: fixtureStart.addingTimeInterval(TimeInterval(i) * fixtureSpacing),
                open: price,
                high: price + 0.5,
                low: price - 0.5,
                close: price,
                volume: 1)
        }
    }()

    // MARK: - 1. Fixture shape

    func testFixtureLength() {
        let candles = Self.fixtureCandles
        XCTAssertEqual(candles.count, 100,
                       "fixture must contain exactly 100 bars")
        // Hand-recompute first and last close with the same formula. Doing it
        // inline (rather than hardcoding a literal) keeps the test in sync if
        // the formula ever evolves on purpose.
        let expectedFirst = 100.0 + 20.0 * sin(2.0 * .pi * 0.0 / 24.0) + 0.1 * 0.0
        let expectedLast = 100.0 + 20.0 * sin(2.0 * .pi * 99.0 / 24.0) + 0.1 * 99.0
        XCTAssertEqual(candles.first!.close, expectedFirst, accuracy: 1e-9)
        XCTAssertEqual(candles.last!.close, expectedLast, accuracy: 1e-9)
        // Spacing sanity: every step is exactly 3600s.
        for i in 1..<candles.count {
            let dt = candles[i].time.timeIntervalSince(candles[i - 1].time)
            XCTAssertEqual(dt, 3600, accuracy: 1e-9,
                           "fixture must use 1-hour spacing")
        }
    }

    // MARK: - 2. SMA crossover

    func testSMACrossoverOnFixture() {
        let strategy = SMACrossoverStrategy(fast: 5, slow: 10)
        let bt = Backtester(strategy: strategy,
                            symbol: "TEST",
                            initialCashCents: 1_000_000_00,
                            feeRate: 0.001,
                            governorConfig: .balanced,
                            barsPerYear: Granularity.hour.barsPerYear)
        let r = bt.run(candles: Self.fixtureCandles)
        XCTAssertEqual(r.equityCurve.count, 100,
                       "equity curve must have one sample per bar")
        XCTAssertGreaterThanOrEqual(r.stats.tradeCount, 1,
                                    "SMA crossover should fire at least once on a 100-bar sine+drift")
        XCTAssertEqual(r.stats.initialEquity.cents, 1_000_000_00,
                       "initial equity must match the constructor argument")
    }

    // MARK: - 3. RSI reversion

    func testRSIReversionOnFixture() {
        let strategy = RSIReversionStrategy(period: 14, oversold: 35, cover: 60)
        let bt = Backtester(strategy: strategy,
                            symbol: "TEST",
                            initialCashCents: 1_000_000_00,
                            feeRate: 0.001,
                            governorConfig: .balanced,
                            barsPerYear: Granularity.hour.barsPerYear)
        let r = bt.run(candles: Self.fixtureCandles)
        XCTAssertEqual(r.equityCurve.count, 100,
                       "equity curve must have one sample per bar")
    }

    // MARK: - 4. Donchian breakout

    func testDonchianOnFixture() {
        let strategy = DonchianBreakoutStrategy(entryPeriod: 20, exitPeriod: 10)
        let bt = Backtester(strategy: strategy,
                            symbol: "TEST",
                            initialCashCents: 1_000_000_00,
                            feeRate: 0.001,
                            governorConfig: .balanced,
                            barsPerYear: Granularity.hour.barsPerYear)
        let r = bt.run(candles: Self.fixtureCandles)
        XCTAssertEqual(r.equityCurve.count, 100,
                       "equity curve must have one sample per bar")
    }

    // MARK: - 5. DCA

    func testDCAOnFixture() {
        // Interval=10 over 100 bars: bars 10, 20, 30, 40, 50, 60, 70, 80, 90
        // fire (bar 0 is skipped per the post-PR-17 guard). That's 9 buys.
        let strategy = DCAStrategy(intervalBars: 10, cashPerBuyCents: 5_000)
        let bt = Backtester(strategy: strategy,
                            symbol: "TEST",
                            initialCashCents: 1_000_000_00,
                            feeRate: 0,
                            governorConfig: .balanced,
                            barsPerYear: Granularity.hour.barsPerYear)
        let r = bt.run(candles: Self.fixtureCandles)
        XCTAssertEqual(r.equityCurve.count, 100)
        XCTAssertEqual(r.trades.count, 9,
                       "DCA at intervalBars=10 over 100 bars should fire exactly 9 buys (bar 0 skipped)")
        for fill in r.trades {
            XCTAssertEqual(fill.order.side, .buy, "DCA fills must all be buys")
        }
    }

    // MARK: - 6. Cross-cutting stats bounds

    func testStatsBoundsOnFixture() {
        // Run every strategy through the fixture and assert universal bounds
        // on the stats. Any NaN/Inf or out-of-range value blows the test.
        let strategies: [any Strategy] = [
            SMACrossoverStrategy(fast: 5, slow: 10),
            RSIReversionStrategy(period: 14, oversold: 35, cover: 60),
            DonchianBreakoutStrategy(entryPeriod: 20, exitPeriod: 10),
            DCAStrategy(intervalBars: 10, cashPerBuyCents: 5_000),
        ]
        for strategy in strategies {
            let bt = Backtester(strategy: strategy,
                                symbol: "TEST",
                                initialCashCents: 1_000_000_00,
                                feeRate: 0.001,
                                governorConfig: .balanced,
                                barsPerYear: Granularity.hour.barsPerYear)
            let stats = bt.run(candles: Self.fixtureCandles).stats
            let label = strategy.name
            XCTAssertGreaterThanOrEqual(stats.winRate, 0,
                                        "\(label): winRate must be >= 0")
            XCTAssertLessThanOrEqual(stats.winRate, 1,
                                     "\(label): winRate must be <= 1")
            XCTAssertGreaterThanOrEqual(stats.maxDrawdownPct, 0,
                                        "\(label): maxDrawdownPct must be >= 0")
            XCTAssertLessThanOrEqual(stats.maxDrawdownPct, 1,
                                     "\(label): maxDrawdownPct must be <= 1")
            XCTAssertGreaterThan(stats.finalEquity.cents, 0,
                                 "\(label): finalEquity must be strictly positive")
            XCTAssertTrue(stats.sharpe.isFinite,
                          "\(label): sharpe must be finite (no NaN, no Inf)")
        }
    }

    // MARK: - 7. Sharpe scaling

    func testSharpeScalesWithBarsPerYear() {
        // DCA at intervalBars=10 over 100 bars produces 9 buys (some equity
        // volatility from fees and mark drift), giving a non-zero Sharpe at
        // both annualization factors. Their ratio should equal sqrt of the
        // bars-per-year ratio, to floating-point tolerance.
        let strategy = DCAStrategy(intervalBars: 10, cashPerBuyCents: 5_000)
        let bt252 = Backtester(strategy: strategy,
                               symbol: "TEST",
                               initialCashCents: 1_000_000_00,
                               feeRate: 0.001,
                               governorConfig: .balanced,
                               barsPerYear: 252)
        let btHour = Backtester(strategy: strategy,
                                symbol: "TEST",
                                initialCashCents: 1_000_000_00,
                                feeRate: 0.001,
                                governorConfig: .balanced,
                                barsPerYear: Granularity.hour.barsPerYear)
        let s1 = bt252.run(candles: Self.fixtureCandles).stats.sharpe
        let s2 = btHour.run(candles: Self.fixtureCandles).stats.sharpe
        XCTAssertNotEqual(s1, 0, "expected non-zero Sharpe with feeRate>0 and trades")
        XCTAssertNotEqual(s2, 0, "expected non-zero Sharpe with feeRate>0 and trades")
        let expectedRatio = (Granularity.hour.barsPerYear / 252.0).squareRoot()
        XCTAssertEqual(s2 / s1, expectedRatio, accuracy: 1e-6,
                       "sharpe(hour) / sharpe(252) should equal sqrt(bpyHour / 252)")
    }
}
