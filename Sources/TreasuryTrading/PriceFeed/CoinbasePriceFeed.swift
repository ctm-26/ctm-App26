import Foundation

/// Coinbase Exchange public market data. No auth, no API keys.
/// Endpoints:
///   GET /products/{id}/candles?granularity=...&start=...&end=...
///   GET /products/{id}/ticker
/// Docs: https://docs.cloud.coinbase.com/exchange/reference/
public struct CoinbasePriceFeed: PriceFeed {
    public let baseURL: URL
    public let session: URLSession

    public init(baseURL: URL = URL(string: "https://api.exchange.coinbase.com")!,
                session: URLSession = .shared)
    {
        self.baseURL = baseURL; self.session = session
    }

    public func candles(symbol: String, granularity: Granularity,
                        start: Date, end: Date) async throws -> [Candle]
    {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("products/\(symbol)/candles"),
            resolvingAgainstBaseURL: false)!
        let iso = ISO8601DateFormatter()
        comps.queryItems = [
            URLQueryItem(name: "granularity", value: String(granularity.rawValue)),
            URLQueryItem(name: "start", value: iso.string(from: start)),
            URLQueryItem(name: "end", value: iso.string(from: end)),
        ]
        let (data, response) = try await get(url: comps.url!)
        try checkHTTP(response, data: data)

        // Coinbase returns: [[time, low, high, open, close, volume], ...]
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[Double]] else {
            throw PriceFeedError.decode("unexpected candle JSON shape")
        }
        return raw.compactMap { row in
            guard row.count >= 6 else { return nil }
            return Candle(
                time: Date(timeIntervalSince1970: row[0]),
                open: row[3], high: row[2], low: row[1],
                close: row[4], volume: row[5])
        }.sorted { $0.time < $1.time }
    }

    public func ticker(symbol: String) async throws -> Double {
        let url = baseURL.appendingPathComponent("products/\(symbol)/ticker")
        let (data, response) = try await get(url: url)
        try checkHTTP(response, data: data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = obj["price"] as? String,
              let price = Double(priceStr)
        else { throw PriceFeedError.decode("ticker missing price") }
        return price
    }

    private func get(url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("TreasuryKernel/0.1", forHTTPHeaderField: "User-Agent")
        do { return try await session.data(for: req) }
        catch { throw PriceFeedError.network("\(error)") }
    }

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 { throw PriceFeedError.rateLimited }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "?"
            throw PriceFeedError.http(http.statusCode, body)
        }
    }
}
