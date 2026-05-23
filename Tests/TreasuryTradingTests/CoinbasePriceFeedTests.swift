import XCTest
@testable import TreasuryTrading

/// Intercepts URL requests so `CoinbasePriceFeed` never touches the network.
/// A per-test stub closure produces the canned `(HTTPURLResponse, Data)` pair.
fileprivate final class MockURLProtocol: URLProtocol {
    /// Stub installed by the active test. Cleared in `tearDown`.
    static var stub: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = MockURLProtocol.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try stub(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class CoinbasePriceFeedTests: XCTestCase {
    private let baseURL = URL(string: "https://example.invalid")!

    private func makeFeed() -> CoinbasePriceFeed {
        let config = URLSessionConfiguration.ephemeral
        // Belt-and-braces: install our protocol *before* any default.
        config.protocolClasses = [MockURLProtocol.self]
        // Make sure nothing slips to `.shared` or a cache.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        return CoinbasePriceFeed(baseURL: baseURL, session: session)
    }

    override func tearDown() {
        MockURLProtocol.stub = nil
        super.tearDown()
    }

    // MARK: - candles

    func testCandlesDecodesCoinbaseShape() async throws {
        // Coinbase candle row: [time, low, high, open, close, volume].
        // 5 rows, intentionally out of chronological order to exercise sort.
        let rows: [[Double]] = [
            [1700000200, 100.0, 110.0, 105.0, 108.0, 12.5],
            [1700000000, 100.0, 110.0, 105.0, 108.0, 12.5],
            [1700000100, 100.0, 110.0, 105.0, 108.0, 12.5],
            [1700000400, 100.0, 110.0, 105.0, 108.0, 12.5],
            [1700000300, 100.0, 110.0, 105.0, 108.0, 12.5],
        ]
        let data = try JSONSerialization.data(withJSONObject: rows)
        MockURLProtocol.stub = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            return (resp, data)
        }

        let feed = makeFeed()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_000_500)
        let candles = try await feed.candles(
            symbol: "BTC-USD", granularity: .minute, start: start, end: end)

        XCTAssertEqual(candles.count, 5)
        // Sorted chronologically.
        let times = candles.map { $0.time.timeIntervalSince1970 }
        XCTAssertEqual(times, times.sorted())
        for c in candles {
            XCTAssertEqual(c.open, 105.0, accuracy: 1e-9)
            XCTAssertEqual(c.high, 110.0, accuracy: 1e-9)
            XCTAssertEqual(c.low, 100.0, accuracy: 1e-9)
            XCTAssertEqual(c.close, 108.0, accuracy: 1e-9)
            XCTAssertEqual(c.volume, 12.5, accuracy: 1e-9)
        }
    }

    // MARK: - ticker

    func testTickerExtractsPrice() async throws {
        let json = #"{"price":"60123.45","trade_id":1}"#.data(using: .utf8)!
        MockURLProtocol.stub = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            return (resp, json)
        }

        let feed = makeFeed()
        let price = try await feed.ticker(symbol: "BTC-USD")
        XCTAssertEqual(price, 60123.45, accuracy: 1e-9)
    }

    // MARK: - HTTP error mapping

    func testHTTP429MapsToRateLimitedError() async {
        MockURLProtocol.stub = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, Data("slow down".utf8))
        }

        let feed = makeFeed()
        do {
            _ = try await feed.ticker(symbol: "BTC-USD")
            XCTFail("expected PriceFeedError.rateLimited to be thrown")
        } catch let error as PriceFeedError {
            if case .rateLimited = error {
                // expected
            } else {
                XCTFail("expected .rateLimited, got \(error)")
            }
        } catch {
            XCTFail("expected PriceFeedError, got \(error)")
        }
    }
}
