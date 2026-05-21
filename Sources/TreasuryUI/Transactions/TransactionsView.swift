import SwiftUI
import TreasuryKernel
import UniformTypeIdentifiers

public struct TransactionsView: View {
    @Environment(AppState.self) private var state
    @State private var transactions: [LedgerTransaction] = []
    @State private var accounts: [Account] = []
    @State private var filter = LedgerService.TransactionFilter()
    @State private var showImport = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
                .padding(.horizontal, 24)
                .padding(.top, 16)
            List(transactions) { row in
                TransactionRow(row: row)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImport = true } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { state.task({ _ = try await state.rules.classifyAll() }) { _ in reload() } }
                    label: { Label("Classify", systemImage: "wand.and.rays") }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportView(accounts: accounts, onComplete: { reload() })
        }
        .task { reload(); reloadAccounts() }
    }

    private var filterBar: some View {
        HStack(spacing: 16) {
            Menu {
                Button("All accounts") { filter.accountId = nil; reload() }
                ForEach(accounts) { a in
                    Button(a.name) { filter.accountId = a.id; reload() }
                }
            } label: {
                Label(currentAccountName, systemImage: "building.columns")
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }

            TextField("YYYY-MM", text: Binding(
                get: { filter.month ?? "" },
                set: { filter.month = $0.isEmpty ? nil : $0; reload() }))
                .frame(width: 110)
                .textFieldStyle(.roundedBorder)

            Toggle("Only unknown", isOn: $filter.includeUncategorizedOnly)
                .toggleStyle(.button)
                .onChange(of: filter.includeUncategorizedOnly) { _, _ in reload() }

            Spacer()
            Text("\(transactions.count) shown").foregroundStyle(.secondary)
        }
    }

    private var currentAccountName: String {
        if let id = filter.accountId, let acc = accounts.first(where: { $0.id == id }) {
            return acc.name
        }
        return "All accounts"
    }

    private func reload() {
        let f = filter
        state.task({ try await state.ledger.transactions(filter: f) }) { self.transactions = $0 }
    }
    private func reloadAccounts() {
        state.task({ try await state.ledger.accounts() }) { self.accounts = $0 }
    }
}

private struct TransactionRow: View {
    let row: LedgerTransaction
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.description).font(.body)
                HStack(spacing: 6) {
                    Text(row.date).font(.caption).foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(row.accountName).font(.caption).foregroundStyle(.secondary)
                    if let c = row.categoryName {
                        Text("•").foregroundStyle(.tertiary)
                        Text(c).font(.caption).foregroundStyle(Theme.strategyColor)
                    } else {
                        Text("•").foregroundStyle(.tertiary)
                        Text("unknown").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(row.amount.formatted())
                .monospacedDigit()
                .foregroundStyle(row.amount.cents >= 0 ? Theme.incomeColor : Theme.spendingColor)
        }
        .padding(.vertical, 6)
    }
}
