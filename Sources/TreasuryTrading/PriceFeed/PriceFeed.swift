import Foundation

public enum Granularity: Int, Sendable, CaseIterable {
    case minute  = 60
    case fiveMin = 300
    case fifteenMin = 900
    case hour    = 3600
    case sixHour = 21600
    case day     = 86400

    public var displayName: String {
        switch self {
        case .minute: return "1m"
        case .fiveMin: return "5m"
        case .fifteenMin: return "15m"
        case .hour: return "1h"
        case .sixHour: return "6h"
        case .day: return "1d"
        }
    }
}

public protocol PriceFeed: Sendable {
    /// Fetch historical candles for a symbol over a closed time range.
    func candles(symbol: String, granularity: Granularity,
                 start: Date, end: Date) async throws -> [Candle]

    /// Current spot price for a symbol.
    func ticker(symbol: String) async throws -> Double
}

public enum PriceFeedError: Error, CustomStringConvertible, Sendable {
    case http(Int, String)
    case decode(String)
    case rateLimited
    case network(String)

    public var description: String {
        switch self {
        case .http(let code, let m): return "HTTP \(code): \(m)"
        case .decode(let m): return "decode error: \(m)"
        case .rateLimited: return "rate limited"
        case .network(let m): return "network: \(m)"
        }
    }
}
