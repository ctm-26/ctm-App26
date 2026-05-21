import Foundation
import SQLite3

public struct ImportService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    /// Import a CSV string into the named account.
    /// - Parameters:
    ///   - csv: full CSV file contents
    ///   - sourceName: filename or URL string, recorded in `import_batches`
    ///   - accountName: target account (must already exist)
    ///   - dryRun: if true, parse and return a result but write nothing
    public func importCSV(_ csv: String,
                          sourceName: String,
                          accountName: String,
                          dryRun: Bool = false) async throws -> ImportResult
    {
        guard let account = try await LedgerService(db: db).findAccount(named: accountName) else {
            throw TreasuryError.notFound("account '\(accountName)'")
        }
        let rows = CSVParser(text: csv).rows()
        guard let header = rows.first else {
            throw TreasuryError.validation("CSV has no rows")
        }
        guard let map = CSVHeaderMap.detect(from: header) else {
            throw TreasuryError.validation(
                "missing required headers: need date, description, and (amount or debit/credit)")
        }
        let dataRows = Array(rows.dropFirst())

        var batchId: Int64? = nil
        if !dryRun {
            batchId = try await db.insert("""
                INSERT INTO import_batches(filename, account_id, row_count, status)
                VALUES(?, ?, 0, 'in_progress');
                """, bind: { dbi, stmt in
                dbi.bindText(stmt, 1, sourceName)
                dbi.bindInt(stmt, 2, account.id)
            })
        }

        var inserted = 0, duplicates = 0, rejected = 0
        var reasons: [String] = []

        if !dryRun { try await db.exec("BEGIN;") }
        for (i, row) in dataRows.enumerated() {
            let lineNo = i + 2 // header is line 1
            guard row.count > max(map.date, map.description) else {
                rejected += 1; reasons.append("line \(lineNo): not enough columns"); continue
            }
            guard let date = DateNormalizer.normalize(row[map.date]) else {
                rejected += 1
                reasons.append("line \(lineNo): bad date '\(row[map.date])'")
                continue
            }
            let desc = row[map.description].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else {
                rejected += 1; reasons.append("line \(lineNo): empty description"); continue
            }
            guard let cents = parseAmount(row: row, map: map) else {
                rejected += 1; reasons.append("line \(lineNo): bad amount"); continue
            }
            if dryRun { inserted += 1; continue }

            do {
                _ = try await db.insert("""
                    INSERT OR IGNORE INTO transactions
                    (account_id, date, description, amount_cents, import_batch_id)
                    VALUES(?, ?, ?, ?, ?);
                    """, bind: { dbi, stmt in
                    dbi.bindInt(stmt, 1, account.id)
                    dbi.bindText(stmt, 2, date)
                    dbi.bindText(stmt, 3, desc)
                    dbi.bindInt(stmt, 4, cents)
                    dbi.bindInt(stmt, 5, batchId)
                })
                // sqlite3_changes() reports rows touched by the most recent
                // INSERT/UPDATE/DELETE; 0 means OR IGNORE skipped a duplicate.
                let n = try await db.changes()
                if n == 0 { duplicates += 1 } else { inserted += 1 }
            } catch {
                rejected += 1
                reasons.append("line \(lineNo): \(error)")
            }
        }
        if !dryRun { try await db.exec("COMMIT;") }

        if !dryRun, let id = batchId {
            try await db.insert("""
                UPDATE import_batches SET row_count = ?, status = ? WHERE id = ?;
                """, bind: { dbi, stmt in
                dbi.bindInt(stmt, 1, Int64(inserted))
                dbi.bindText(stmt, 2, rejected > 0 ? "completed_with_errors" : "completed")
                dbi.bindInt(stmt, 3, id)
            })
            try await db.appendAudit(action: "import",
                details: "file=\(sourceName) account=\(account.name) rows=\(dataRows.count) inserted=\(inserted) duplicates=\(duplicates) rejected=\(rejected) batch=\(id)")
        }

        return ImportResult(totalRows: dataRows.count, inserted: inserted,
                            duplicates: duplicates, rejected: rejected,
                            rejectedReasons: reasons, batchId: batchId)
    }

    private func parseAmount(row: [String], map: CSVHeaderMap) -> Int64? {
        if let ai = map.amount, row.count > ai {
            let raw = row[ai].trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let m = Money.parse(raw) { return m.cents }
        }
        var debit: Int64 = 0, credit: Int64 = 0
        var hadAny = false
        if let i = map.debit, row.count > i {
            let raw = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let m = Money.parse(raw) {
                debit = m.cents < 0 ? -m.cents : m.cents
                hadAny = true
            }
        }
        if let i = map.credit, row.count > i {
            let raw = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let m = Money.parse(raw) {
                credit = m.cents < 0 ? -m.cents : m.cents
                hadAny = true
            }
        }
        return hadAny ? credit - debit : nil
    }
}
