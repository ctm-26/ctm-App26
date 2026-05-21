import Foundation

public struct Account: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public var type: String
    public var createdAt: String
    public init(id: Int64, name: String, type: String, createdAt: String) {
        self.id = id; self.name = name; self.type = type; self.createdAt = createdAt
    }
}

public struct Category: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public init(id: Int64, name: String) { self.id = id; self.name = name }
}

public struct Rule: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var pattern: String
    public var categoryId: Int64
    public var categoryName: String
    public var priority: Int
    public init(id: Int64, pattern: String, categoryId: Int64,
                categoryName: String, priority: Int) {
        self.id = id; self.pattern = pattern; self.categoryId = categoryId
        self.categoryName = categoryName; self.priority = priority
    }
}

public struct LedgerTransaction: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let accountId: Int64
    public let accountName: String
    public let date: String      // ISO YYYY-MM-DD
    public let description: String
    public let amount: Money
    public let categoryId: Int64?
    public let categoryName: String?
    public init(id: Int64, accountId: Int64, accountName: String,
                date: String, description: String, amount: Money,
                categoryId: Int64?, categoryName: String?) {
        self.id = id; self.accountId = accountId; self.accountName = accountName
        self.date = date; self.description = description; self.amount = amount
        self.categoryId = categoryId; self.categoryName = categoryName
    }
}

public struct ImportBatch: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let filename: String
    public let accountId: Int64
    public let importedAt: String
    public var rowCount: Int
    public var status: String
}

public struct AuditEvent: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let action: String
    public let details: String?
    public let createdAt: String
}

public struct CategoryRollup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let amount: Money
    public let count: Int
}

public struct AccountRollup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let net: Money
    public let count: Int
}

public struct MonthlyReport: Sendable {
    public let month: String   // YYYY-MM
    public let transactionCount: Int
    public let income: Money
    public let spending: Money
    public var net: Money { Money(cents: income.cents + spending.cents) }
    public let byCategory: [CategoryRollup]
    public let byAccount: [AccountRollup]
}

public struct ImportResult: Sendable {
    public let totalRows: Int
    public let inserted: Int
    public let duplicates: Int
    public let rejected: Int
    public let rejectedReasons: [String]
    public let batchId: Int64?
}

public enum TreasuryError: Error, CustomStringConvertible, Sendable {
    case sqlite(String)
    case notFound(String)
    case validation(String)
    case io(String)

    public var description: String {
        switch self {
        case .sqlite(let m): return "sqlite: \(m)"
        case .notFound(let m): return "not found: \(m)"
        case .validation(let m): return "invalid: \(m)"
        case .io(let m): return "io: \(m)"
        }
    }
}
