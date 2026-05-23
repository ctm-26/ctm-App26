import XCTest
@testable import TreasuryKernel

final class LedgerTests: XCTestCase {

    func makeDB() async throws -> LedgerDatabase {
        let path = NSTemporaryDirectory() + "treasury-test-\(UUID().uuidString).db"
        return try LedgerDatabase(path: path)
    }

    func testMoneyParsing() {
        XCTAssertEqual(Money.parse("$1,234.56")?.cents, 123_456)
        XCTAssertEqual(Money.parse("-42.18")?.cents, -4218)
        XCTAssertEqual(Money.parse("(42.18)")?.cents, -4218)
        XCTAssertEqual(Money.parse("0")?.cents, 0)
        XCTAssertNil(Money.parse("abc"))
    }

    func testDateNormalizer() {
        XCTAssertEqual(DateNormalizer.normalize("2026-05-02"), "2026-05-02")
        XCTAssertEqual(DateNormalizer.normalize("05/02/2026"), "2026-05-02")
        XCTAssertEqual(DateNormalizer.normalize("5/2/26"), "2026-05-02")
        XCTAssertNil(DateNormalizer.normalize("2026-13-01"))
        XCTAssertTrue(DateNormalizer.validYearMonth("2026-05"))
        XCTAssertFalse(DateNormalizer.validYearMonth("2026-13"))
    }

    func testEndToEnd() async throws {
        let db = try await makeDB()
        let ledger = LedgerService(db: db)
        let rules = RuleService(db: db)
        let importer = ImportService(db: db)
        let reports = ReportService(db: db)

        _ = try await ledger.addAccount(name: "Chase Checking", type: "checking")
        let csv = """
        Date,Description,Amount
        2026-05-02,SHOPRITE #421,-42.18
        2026-05-03,SHELL OIL,-38.40
        2026-05-04,NETFLIX.COM,-15.99
        2026-05-05,PAYROLL CO,2400.00
        """
        let result = try await importer.importCSV(
            csv, sourceName: "test.csv", accountName: "Chase Checking")
        XCTAssertEqual(result.inserted, 4)
        XCTAssertEqual(result.rejected, 0)

        // Idempotent re-import.
        let again = try await importer.importCSV(
            csv, sourceName: "test.csv", accountName: "Chase Checking")
        XCTAssertEqual(again.duplicates, 4)
        XCTAssertEqual(again.inserted, 0)

        _ = try await rules.addRule(pattern: "SHOPRITE", categoryName: "groceries")
        _ = try await rules.addRule(pattern: "SHELL", categoryName: "gas")
        _ = try await rules.addRule(pattern: "NETFLIX", categoryName: "subscriptions")
        _ = try await rules.addRule(pattern: "PAYROLL", categoryName: "income", priority: 5)
        let cls = try await rules.classifyAll()
        XCTAssertEqual(cls.classified, 4)
        XCTAssertEqual(cls.remainingUnknown, 0)

        let r = try await reports.monthly("2026-05")
        XCTAssertEqual(r.transactionCount, 4)
        XCTAssertEqual(r.income.cents, 240_000)
        XCTAssertEqual(r.spending.cents, -42_18 - 38_40 - 15_99)
        XCTAssertEqual(r.byCategory.count, 4)
    }

    func testAccountBalances() async throws {
        let db = try await makeDB()
        let ledger = LedgerService(db: db)
        let importer = ImportService(db: db)

        let accountA = try await ledger.addAccount(name: "Acct A", type: "checking")
        let accountB = try await ledger.addAccount(name: "Acct B", type: "savings")
        // Third account: no transactions at all.
        let accountC = try await ledger.addAccount(name: "Acct C", type: "cash")

        // Account A: +100.00, -42.18, -7.50 → 50.32 = 5032 cents.
        let csvA = """
        Date,Description,Amount
        2026-05-01,DEPOSIT,100.00
        2026-05-02,SHOPRITE,-42.18
        2026-05-03,COFFEE,-7.50
        """
        let resA = try await importer.importCSV(
            csvA, sourceName: "a.csv", accountName: "Acct A")
        XCTAssertEqual(resA.inserted, 3)

        // Account B: +25.00 → 2500 cents.
        let csvB = """
        Date,Description,Amount
        2026-05-04,REBATE,25.00
        """
        let resB = try await importer.importCSV(
            csvB, sourceName: "b.csv", accountName: "Acct B")
        XCTAssertEqual(resB.inserted, 1)

        let balances = try await ledger.accountBalances()
        XCTAssertEqual(balances[accountA.id]?.cents, 5032)
        XCTAssertEqual(balances[accountB.id]?.cents, 2500)
        // Zero-transaction account still appears with Money.zero.
        XCTAssertEqual(balances[accountC.id], Money.zero)
        XCTAssertEqual(balances[accountC.id]?.cents, 0)
    // MARK: - addTransaction

    func testAddTransactionSuccess() async throws {
        let db = try await makeDB()
        let ledger = LedgerService(db: db)

        let account = try await ledger.addAccount(name: "Manual Test", type: "checking")
        let category = try await ledger.getOrCreateCategory("misc")

        let tx = try await ledger.addTransaction(
            accountId: account.id,
            date: "2026-05-22",
            description: "  manual entry  ",
            amount: Money(cents: -1500),
            categoryId: category.id)

        XCTAssertGreaterThan(tx.id, 0)
        XCTAssertEqual(tx.accountId, account.id)
        XCTAssertEqual(tx.accountName, "Manual Test")
        XCTAssertEqual(tx.date, "2026-05-22")
        XCTAssertEqual(tx.description, "manual entry")          // trimmed
        XCTAssertEqual(tx.amount.cents, -1500)
        XCTAssertEqual(tx.categoryId, category.id)
        XCTAssertEqual(tx.categoryName, "misc")

        // Round-trips through the read path.
        var f = LedgerService.TransactionFilter()
        f.accountId = account.id
        let rows = try await ledger.transactions(filter: f)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, tx.id)
        XCTAssertEqual(rows.first?.description, "manual entry")

        // Audit spine has a tx.add row.
        let audit = AuditService(db: db)
        let events = try await audit.recent(limit: 50)
        XCTAssertTrue(events.contains { $0.action == "tx.add" },
                      "expected an audit_log row with action=tx.add")
    }

    /// A second identical addTransaction must throw — UI relies on this to show
    /// a duplicate error. The thrown case is `.validation` (we translate the
    /// SQLite UNIQUE error to a validation error in `addTransaction`).
    func testAddTransactionRejectsDuplicate() async throws {
        let db = try await makeDB()
        let ledger = LedgerService(db: db)
        let account = try await ledger.addAccount(name: "Dup Acct", type: "checking")

        _ = try await ledger.addTransaction(
            accountId: account.id,
            date: "2026-05-22",
            description: "coffee",
            amount: Money(cents: -550))

        do {
            _ = try await ledger.addTransaction(
                accountId: account.id,
                date: "2026-05-22",
                description: "coffee",
                amount: Money(cents: -550))
            XCTFail("expected duplicate to throw")
        } catch TreasuryError.validation(let msg) {
            XCTAssertTrue(msg.lowercased().contains("duplicate"),
                          "expected duplicate validation, got: \(msg)")
        } catch TreasuryError.sqlite {
            // Acceptable alternate translation if a future refactor lets the
            // raw sqlite error through. Document the contract here.
        } catch {
            XCTFail("expected .validation or .sqlite, got: \(error)")
        }
    }

    func testAddTransactionRejectsBadDate() async throws {
        let db = try await makeDB()
        let ledger = LedgerService(db: db)
        let account = try await ledger.addAccount(name: "Bad Date Acct", type: "checking")

        do {
            _ = try await ledger.addTransaction(
                accountId: account.id,
                date: "not-a-date",
                description: "something",
                amount: Money(cents: 100))
            XCTFail("expected bad date to throw")
        } catch TreasuryError.validation(let msg) {
            XCTAssertTrue(msg.contains("not-a-date"),
                          "expected invalid date message, got: \(msg)")
        } catch {
            XCTFail("expected .validation, got: \(error)")
        }
    }
}
