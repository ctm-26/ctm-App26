import Foundation
import Observation
import TreasuryKernel
import TreasuryTrading

@MainActor
@Observable
public final class AppState {
    public let db: LedgerDatabase
    public let ledger: LedgerService
    public let rules: RuleService
    public let importer: ImportService
    public let reports: ReportService
    public let audit: AuditService
    public let portfolios: PortfolioStore

    public var feed: any PriceFeed
    public var engine: TradingEngine?
    public var currentPortfolio: PortfolioStore.PortfolioRow?
    public var lastError: String?

    public init(db: LedgerDatabase, feed: any PriceFeed = CoinbasePriceFeed()) {
        self.db = db
        self.ledger = LedgerService(db: db)
        self.rules = RuleService(db: db)
        self.importer = ImportService(db: db)
        self.reports = ReportService(db: db)
        self.audit = AuditService(db: db)
        self.portfolios = PortfolioStore(db: db)
        self.feed = feed
    }

    /// Helper for views to wrap async calls and surface errors uniformly.
    /// Both `body` and `onResult` run on the MainActor so views can mutate
    /// state directly inside `onResult`.
    public func task<T: Sendable>(
        _ body: @escaping @MainActor () async throws -> T,
        onResult: @escaping @MainActor (T) -> Void = { _ in })
    {
        Task { @MainActor in
            do { onResult(try await body()) }
            catch { self.lastError = "\(error)" }
        }
    }

    /// One-shot factory: open `treasury.db` in the iOS Documents directory and
    /// return a wired-up AppState. Used by the iPad app on launch.
    public static func makeDefault() throws -> AppState {
        let url = try defaultDatabaseURL()
        let db = try LedgerDatabase(path: url.path)
        return AppState(db: db)
    }

    public static func defaultDatabaseURL() throws -> URL {
        #if os(iOS)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("TreasuryKernel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #endif
        return dir.appendingPathComponent("treasury.db")
    }
}
