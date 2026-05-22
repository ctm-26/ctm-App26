import Foundation
import SQLite3

/// Reads + writes for the ledger core (accounts, categories, transactions).
public struct LedgerService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    // MARK: - Accounts

    public func accounts() async throws -> [Account] {
        try await db.query("""
            SELECT a.id, a.name, a.type, a.created_at
            FROM accounts a ORDER BY a.name;
            """) { dbi, stmt in
            Account(
                id: sqlite3_column_int64(stmt, 0),
                name: dbi.text(stmt, 1),
                type: dbi.text(stmt, 2),
                createdAt: dbi.text(stmt, 3)
            )
        }
    }

    public func addAccount(name: String, type: String) async throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TreasuryError.validation("account name is empty") }
        let id = try await db.insert(
            "INSERT INTO accounts(name, type) VALUES(?, ?);",
            bind: { db, stmt in
                db.bindText(stmt, 1, trimmed); db.bindText(stmt, 2, type)
            })
        try await db.appendAudit(action: "account.add",
                                 details: "name=\(trimmed) type=\(type)")
        return Account(id: id, name: trimmed, type: type, createdAt: "")
    }

    public func findAccount(named name: String) async throws -> Account? {
        try await db.queryOne("""
            SELECT id, name, type, created_at FROM accounts WHERE name = ? LIMIT 1;
            """, bind: { db, stmt in db.bindText(stmt, 1, name) }) { dbi, stmt in
            Account(
                id: sqlite3_column_int64(stmt, 0),
                name: dbi.text(stmt, 1),
                type: dbi.text(stmt, 2),
                createdAt: dbi.text(stmt, 3)
            )
        }
    }

    // MARK: - Categories

    public func categories() async throws -> [Category] {
        try await db.query("SELECT id, name FROM categories ORDER BY name;") { dbi, stmt in
            Category(id: sqlite3_column_int64(stmt, 0),
                     name: dbi.text(stmt, 1))
        }
    }

    public func getOrCreateCategory(_ name: String) async throws -> Category {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TreasuryError.validation("category name empty") }
        if let existing = try await db.queryOne(
            "SELECT id, name FROM categories WHERE name = ? COLLATE NOCASE LIMIT 1;",
            bind: { db, stmt in db.bindText(stmt, 1, trimmed) },
            map: { dbi, stmt in
                Category(id: sqlite3_column_int64(stmt, 0),
                         name: dbi.text(stmt, 1))
            })
        { return existing }
        let id = try await db.insert(
            "INSERT INTO categories(name) VALUES(?);",
            bind: { db, stmt in db.bindText(stmt, 1, trimmed) })
        try await db.appendAudit(action: "category.add", details: "name=\(trimmed) id=\(id)")
        return Category(id: id, name: trimmed)
    }

    // MARK: - Transactions

    public struct TransactionFilter: Sendable {
        public var accountId: Int64?
        public var month: String?      // YYYY-MM
        public var categoryName: String?
        public var includeUncategorizedOnly: Bool = false
        public var limit: Int = 500
        public init() {}
    }

    public func transactions(filter: TransactionFilter = TransactionFilter())
        async throws -> [LedgerTransaction]
    {
        var sql = """
        SELECT t.id, t.account_id, a.name, t.date, t.description, t.amount_cents,
               t.category_id, c.name
        FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE 1=1
        """
        if filter.accountId != nil { sql += " AND t.account_id = ?" }
        if filter.month != nil { sql += " AND substr(t.date, 1, 7) = ?" }
        if filter.includeUncategorizedOnly {
            sql += " AND t.category_id IS NULL"
        } else if filter.categoryName != nil {
            sql += " AND c.name = ? COLLATE NOCASE"
        }
        sql += " ORDER BY t.date DESC, t.id DESC LIMIT ?;"

        return try await db.query(sql, bind: { dbi, stmt in
            var idx: Int32 = 1
            if let a = filter.accountId { dbi.bindInt(stmt, idx, a); idx += 1 }
            if let m = filter.month { dbi.bindText(stmt, idx, m); idx += 1 }
            if !filter.includeUncategorizedOnly, let c = filter.categoryName {
                dbi.bindText(stmt, idx, c); idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(filter.limit))
        }) { dbi, stmt in
            LedgerTransaction(
                id: sqlite3_column_int64(stmt, 0),
                accountId: sqlite3_column_int64(stmt, 1),
                accountName: dbi.text(stmt, 2),
                date: dbi.text(stmt, 3),
                description: dbi.text(stmt, 4),
                amount: Money(cents: sqlite3_column_int64(stmt, 5)),
                categoryId: sqlite3_column_type(stmt, 6) == SQLITE_NULL ?
                    nil : sqlite3_column_int64(stmt, 6),
                categoryName: dbi.optionalText(stmt, 7)
            )
        }
    }

    public func setCategory(transactionId: Int64, categoryId: Int64?) async throws {
        try await db.insert(
            "UPDATE transactions SET category_id = ? WHERE id = ?;",
            bind: { dbi, stmt in
                dbi.bindInt(stmt, 1, categoryId)
                dbi.bindInt(stmt, 2, transactionId)
            })
        try await db.appendAudit(action: "tx.recategorize",
                                 details: "id=\(transactionId) cat=\(categoryId.map(String.init) ?? "null")")
    }

    public func deleteTransaction(_ id: Int64) async throws {
        try await db.insert(
            "DELETE FROM transactions WHERE id = ?;",
            bind: { dbi, stmt in dbi.bindInt(stmt, 1, id) })
        try await db.appendAudit(action: "tx.delete", details: "id=\(id)")
    }
}
