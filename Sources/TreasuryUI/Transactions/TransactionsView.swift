import SwiftUI
import TreasuryKernel
import UniformTypeIdentifiers

#if canImport(UIKit)

public struct TransactionsView: View {
    @Environment(AppState.self) private var state
    @State private var transactions: [LedgerTransaction] = []
    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var filter = LedgerService.TransactionFilter()
    @State private var showImport = false
    @State private var showAdd = false
    @State private var recategorizeTarget: LedgerTransaction?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
                .padding(.horizontal, 24)
                .padding(.top, 16)
            List(transactions) { row in
                TransactionRow(row: row)
                    .contextMenu {
                        categoryContextMenu(for: row)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            recategorizeTarget = row
                        } label: {
                            Label("Recategorize\u{2026}", systemImage: "tag")
                        }
                        .tint(.blue)
                    }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showImport = true } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { state.task({ _ = try await state.rules.classifyAll() }) { _ in reload() } }
                    label: { Label("Classify", systemImage: "wand.and.rays") }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportView(accounts: accounts, onComplete: { reload() })
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionSheet(
                accounts: accounts,
                categories: categories,
                onSaved: {
                    showAdd = false
                    reload()
                },
                onCancel: { showAdd = false }
            )
        }
        .sheet(item: $recategorizeTarget) { target in
            RecategorizeSheet(
                transaction: target,
                categories: categories,
                onSelect: { newCategoryId in
                    recategorizeTarget = nil
                    applyCategory(transactionId: target.id, categoryId: newCategoryId)
                },
                onCancel: { recategorizeTarget = nil }
            )
            .presentationDetents([.medium])
        }
        .refreshable {
            let f = filter
            do {
                let t = try await state.ledger.transactions(filter: f)
                let a = try await state.ledger.accounts()
                let c = try await state.ledger.categories()
                self.transactions = t
                self.accounts = a
                self.categories = c
            } catch {
                state.lastError = "\(error)"
            }
        }
        .task { reload(); reloadAccounts(); reloadCategories() }
    }

    @ViewBuilder
    private func categoryContextMenu(for row: LedgerTransaction) -> some View {
        Button("Current: \(row.categoryName ?? "(unknown)")") {}
            .disabled(true)
        Divider()
        if categories.isEmpty {
            Button("No categories defined \u{2014} add one in Rules.") {}
                .disabled(true)
        } else {
            ForEach(categories) { cat in
                Button {
                    applyCategory(transactionId: row.id, categoryId: cat.id)
                } label: {
                    if row.categoryId == cat.id {
                        Label(cat.name, systemImage: "checkmark")
                    } else {
                        Text(cat.name)
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                applyCategory(transactionId: row.id, categoryId: nil)
            } label: {
                Label("Clear category", systemImage: "xmark.circle")
            }
        }
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
    private func reloadCategories() {
        state.task({ try await state.ledger.categories() }) { self.categories = $0 }
    }

    private func applyCategory(transactionId: Int64, categoryId: Int64?) {
        state.task({
            try await state.ledger.setCategory(transactionId: transactionId,
                                               categoryId: categoryId)
        }) { _ in
            reload()
        }
    }
}

fileprivate struct RecategorizeSheet: View {
    let transaction: LedgerTransaction
    let categories: [Category]
    let onSelect: (Int64?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            if transaction.categoryId == nil {
                                Image(systemName: "checkmark")
                            }
                            Text("(unknown) \u{2014} Clear")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }
                if categories.isEmpty {
                    Section {
                        Text("No categories defined \u{2014} add one in Rules.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Categories") {
                        ForEach(categories) { cat in
                            Button {
                                onSelect(cat.id)
                            } label: {
                                HStack {
                                    if transaction.categoryId == cat.id {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(cat.name)
                                    Spacer()
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Recategorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}

fileprivate struct AddTransactionSheet: View {
    @Environment(AppState.self) private var state

    let accounts: [Account]
    let categories: [Category]
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var selectedAccount: Account?
    @State private var date: Date = Date()
    @State private var description: String = ""
    @State private var amountText: String = ""
    @State private var selectedCategoryId: Int64? = nil
    @State private var saving = false

    private var parsedAmount: Money? { Money.parse(amountText) }
    private var amountInvalid: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount == nil
    }
    private var canSave: Bool {
        selectedAccount != nil
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount != nil
            && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select").tag(nil as Account?)
                        ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Section("Details") {
                    DatePicker("Date",
                               selection: $date,
                               displayedComponents: [.date])
                    TextField("Description", text: $description)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Amount (e.g. -42.18 or 1,234.56)",
                                  text: $amountText)
                        #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                        #endif
                        if amountInvalid {
                            Text("Cannot parse amount")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("(unknown)").tag(nil as Int64?)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .navigationTitle("Add Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let account = selectedAccount,
              let amount = parsedAmount else { return }
        let isoDate = Self.isoString(from: date)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cid = selectedCategoryId
        saving = true
        state.task({
            try await state.ledger.addTransaction(
                accountId: account.id,
                date: isoDate,
                description: desc,
                amount: amount,
                categoryId: cid)
        }) { _ in
            saving = false
            onSaved()
        }
    }

    private static func isoString(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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

#endif
