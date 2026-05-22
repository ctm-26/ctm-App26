import Foundation
import SQLite3

/// Rule engine: deterministic case-insensitive substring match,
/// ordered by (priority ASC, id ASC). First match wins.
public struct RuleService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    public func rules() async throws -> [Rule] {
        try await db.query("""
            SELECT r.id, r.pattern, r.category_id, c.name, r.priority
            FROM category_rules r JOIN categories c ON c.id = r.category_id
            ORDER BY r.priority ASC, r.id ASC;
            """) { dbi, stmt in
            Rule(id: sqlite3_column_int64(stmt, 0),
                 pattern: dbi.text(stmt, 1),
                 categoryId: sqlite3_column_int64(stmt, 2),
                 categoryName: dbi.text(stmt, 3),
                 priority: Int(sqlite3_column_int(stmt, 4)))
        }
    }

    public func addRule(pattern: String, categoryName: String, priority: Int = 100) async throws -> Rule {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TreasuryError.validation("rule pattern empty") }
        let category = try await LedgerService(db: db).getOrCreateCategory(categoryName)
        let id = try await db.insert(
            "INSERT INTO category_rules(pattern, category_id, priority) VALUES(?, ?, ?);",
            bind: { dbi, stmt in
                dbi.bindText(stmt, 1, trimmed)
                dbi.bindInt(stmt, 2, category.id)
                sqlite3_bind_int(stmt, 3, Int32(priority))
            })
        try await db.appendAudit(action: "rule.add",
                                 details: "pattern=\(trimmed) category=\(category.name) priority=\(priority)")
        return Rule(id: id, pattern: trimmed, categoryId: category.id,
                    categoryName: category.name, priority: priority)
    }

    public func removeRule(id: Int64) async throws {
        try await db.insert("DELETE FROM category_rules WHERE id = ?;",
                            bind: { dbi, stmt in dbi.bindInt(stmt, 1, id) })
        try await db.appendAudit(action: "rule.remove", details: "id=\(id)")
    }

    public struct ClassifyResult: Sendable {
        public let classified: Int
        public let remainingUnknown: Int
    }

    /// Apply rules to all `category_id IS NULL` transactions. Same semantics as
    /// the C kernel: first match wins by priority/id; unknown stays NULL.
    public func classifyAll() async throws -> ClassifyResult {
        let rules = try await self.rules()

        // Pull uncategorized rows.
        struct Row { let id: Int64; let desc: String }
        let rows: [Row] = try await db.query("""
            SELECT id, description FROM transactions WHERE category_id IS NULL ORDER BY id;
            """) { dbi, stmt in
            Row(id: sqlite3_column_int64(stmt, 0),
                desc: dbi.text(stmt, 1))
        }

        var classified = 0
        var unknown = 0
        try await db.exec("BEGIN;")
        do {
            for row in rows {
                var match: Int64? = nil
                for rule in rules {
                    if row.desc.range(of: rule.pattern, options: .caseInsensitive) != nil {
                        match = rule.categoryId
                        break
                    }
                }
                if let cat = match {
                    try await db.insert(
                        "UPDATE transactions SET category_id = ? WHERE id = ?;",
                        bind: { dbi, stmt in
                            dbi.bindInt(stmt, 1, cat); dbi.bindInt(stmt, 2, row.id)
                        })
                    classified += 1
                } else {
                    unknown += 1
                }
            }
            try await db.exec("COMMIT;")
        } catch {
            _ = try? await db.exec("ROLLBACK;")
            throw error
        }
        try await db.appendAudit(action: "classify",
                                 details: "classified=\(classified) unknown=\(unknown)")
        return ClassifyResult(classified: classified, remainingUnknown: unknown)
    }
}
