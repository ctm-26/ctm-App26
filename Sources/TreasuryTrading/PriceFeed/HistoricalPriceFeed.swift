import Foundation

/// In-memory price feed for deterministic backtests.
public struct HistoricalPriceFeed: PriceFeed {
    public let series: [String: [Candle]]

    public init(series: [String: [Candle]]) { self.series = series }

    public func candles(symbol: String, granularity: Granularity,
                        start: Date, end: Date) async throws -> [Candle]
    {
        (series[symbol] ?? []).filter { $0.time >= start && $0.time <= end }
    }

    public func ticker(symbol: String) async throws -> Double {
        series[symbol]?.last?.close ?? 0
    }

    /// Build from a Coinbase-shaped CSV: time,low,high,open,close,volume.
    public static func fromCSV(_ csv: String, symbol: String) -> HistoricalPriceFeed {
        var candles: [Candle] = []
        for line in csv.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: ",").map(String.init)
            guard parts.count >= 6 else { continue }
            guard let t = Double(parts[0]),
                  let l = Double(parts[1]), let h = Double(parts[2]),
                  let o = Double(parts[3]), let c = Double(parts[4]),
                  let v = Double(parts[5])
            else { continue }
            candles.append(Candle(time: Date(timeIntervalSince1970: t),
                                  open: o, high: h, low: l, close: c, volume: v))
        }
        return HistoricalPriceFeed(series: [symbol: candles.sorted { $0.time < $1.time }])
    }
}
