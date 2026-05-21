import Foundation

/// The ledger schema. Must stay byte-for-byte compatible with the schema
/// emitted by TreasuryKernel/src/db.c so that both the CLI and the iPad app
/// can open the same SQLite file.
public enum Schema {
    public static let version = 1

    public static let migrations: [String] = [
        """
        PRAGMA foreign_keys = ON;
        """,
        """
        CREATE TABLE IF NOT EXISTS accounts (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          type TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS category_rules (
          id INTEGER PRIMARY KEY,
          pattern TEXT NOT NULL,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
          priority INTEGER NOT NULL DEFAULT 100,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_rules_priority ON category_rules(priority);
        """,
        """
        CREATE TABLE IF NOT EXISTS import_batches (
          id INTEGER PRIMARY KEY,
          filename TEXT NOT NULL,
          account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          imported_at TEXT NOT NULL DEFAULT (datetime('now')),
          row_count INTEGER NOT NULL,
          status TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS transactions (
          id INTEGER PRIMARY KEY,
          account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          date TEXT NOT NULL,
          description TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,
          category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
          import_batch_id INTEGER REFERENCES import_batches(id) ON DELETE SET NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          UNIQUE(account_id, date, description, amount_cents)
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);
        CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);
        CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);
        """,
        """
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY,
          action TEXT NOT NULL,
          details TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """,
        // Trading lab tables (iPad/Mac only; the C CLI ignores them).
        """
        CREATE TABLE IF NOT EXISTS paper_portfolios (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          base_currency TEXT NOT NULL DEFAULT 'USD',
          cash_cents INTEGER NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS paper_positions (
          id INTEGER PRIMARY KEY,
          portfolio_id INTEGER NOT NULL REFERENCES paper_portfolios(id) ON DELETE CASCADE,
          symbol TEXT NOT NULL,
          qty REAL NOT NULL DEFAULT 0,
          avg_cost_cents INTEGER NOT NULL DEFAULT 0,
          UNIQUE(portfolio_id, symbol)
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS paper_trades (
          id INTEGER PRIMARY KEY,
          portfolio_id INTEGER NOT NULL REFERENCES paper_portfolios(id) ON DELETE CASCADE,
          symbol TEXT NOT NULL,
          side TEXT NOT NULL,          -- 'buy' or 'sell'
          qty REAL NOT NULL,
          price_cents INTEGER NOT NULL,
          fee_cents INTEGER NOT NULL DEFAULT 0,
          strategy TEXT,
          reason TEXT,
          executed_at TEXT NOT NULL
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_paper_trades_portfolio
          ON paper_trades(portfolio_id, executed_at);
        """,
        """
        CREATE TABLE IF NOT EXISTS paper_equity_points (
          id INTEGER PRIMARY KEY,
          portfolio_id INTEGER NOT NULL REFERENCES paper_portfolios(id) ON DELETE CASCADE,
          at TEXT NOT NULL,
          equity_cents INTEGER NOT NULL,
          cash_cents INTEGER NOT NULL,
          UNIQUE(portfolio_id, at)
        );
        """,
    ]
}
