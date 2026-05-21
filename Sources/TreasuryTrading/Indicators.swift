import Foundation

/// Stateless indicators. Each takes a closing-price series and returns one value
/// per input bar (with the early-period values as nil where the indicator
/// hasn't warmed up yet).
public enum Indicators {

    public static func sma(_ x: [Double], period: Int) -> [Double?] {
        guard period > 0, !x.isEmpty else { return [] }
        var out: [Double?] = Array(repeating: nil, count: x.count)
        if x.count < period { return out }
        var sum = 0.0
        for i in 0..<x.count {
            sum += x[i]
            if i >= period { sum -= x[i - period] }
            if i >= period - 1 { out[i] = sum / Double(period) }
        }
        return out
    }

    public static func ema(_ x: [Double], period: Int) -> [Double?] {
        guard period > 0, !x.isEmpty else { return [] }
        var out: [Double?] = Array(repeating: nil, count: x.count)
        if x.count < period { return out }
        let k = 2.0 / (Double(period) + 1.0)
        let seed = x.prefix(period).reduce(0.0, +) / Double(period)
        out[period - 1] = seed
        var prev = seed
        for i in period..<x.count {
            let v = x[i] * k + prev * (1 - k)
            out[i] = v
            prev = v
        }
        return out
    }

    public static func rsi(_ x: [Double], period: Int = 14) -> [Double?] {
        guard period > 0, x.count > period else {
            return Array(repeating: nil, count: x.count)
        }
        var out: [Double?] = Array(repeating: nil, count: x.count)
        var gain = 0.0, loss = 0.0
        for i in 1...period {
            let d = x[i] - x[i - 1]
            if d >= 0 { gain += d } else { loss -= d }
        }
        var avgGain = gain / Double(period)
        var avgLoss = loss / Double(period)
        out[period] = rsiValue(avgGain: avgGain, avgLoss: avgLoss)
        for i in (period + 1)..<x.count {
            let d = x[i] - x[i - 1]
            let g = d > 0 ? d : 0
            let l = d < 0 ? -d : 0
            avgGain = (avgGain * Double(period - 1) + g) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + l) / Double(period)
            out[i] = rsiValue(avgGain: avgGain, avgLoss: avgLoss)
        }
        return out
    }

    private static func rsiValue(avgGain: Double, avgLoss: Double) -> Double {
        guard avgLoss > 0 else { return 100 }
        let rs = avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }

    /// Highest high over the trailing `period` bars (inclusive of current).
    public static func donchianHigh(_ highs: [Double], period: Int) -> [Double?] {
        rollingMax(highs, period: period)
    }

    public static func donchianLow(_ lows: [Double], period: Int) -> [Double?] {
        rollingMin(lows, period: period)
    }

    private static func rollingMax(_ x: [Double], period: Int) -> [Double?] {
        var out: [Double?] = Array(repeating: nil, count: x.count)
        guard period > 0 else { return out }
        for i in 0..<x.count where i + 1 >= period {
            let window = x[(i - period + 1)...i]
            out[i] = window.max()
        }
        return out
    }

    private static func rollingMin(_ x: [Double], period: Int) -> [Double?] {
        var out: [Double?] = Array(repeating: nil, count: x.count)
        guard period > 0 else { return out }
        for i in 0..<x.count where i + 1 >= period {
            let window = x[(i - period + 1)...i]
            out[i] = window.min()
        }
        return out
    }

    /// Average True Range; needed by the risk governor for position sizing.
    public static func atr(highs: [Double], lows: [Double], closes: [Double],
                           period: Int = 14) -> [Double?]
    {
        let n = closes.count
        var tr: [Double] = Array(repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 { tr[i] = highs[i] - lows[i] }
            else {
                tr[i] = max(
                    highs[i] - lows[i],
                    abs(highs[i] - closes[i - 1]),
                    abs(lows[i] - closes[i - 1]))
            }
        }
        return sma(tr, period: period)
    }
}
