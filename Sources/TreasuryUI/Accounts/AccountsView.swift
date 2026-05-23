import SwiftUI
import TreasuryKernel

#if canImport(UIKit)

public struct AccountsView: View {
    @Environment(AppState.self) private var state
    @State private var accounts: [Account] = []
    @State private var balances: [Int64: Money] = [:]
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newType: String = "checking"
    @State private var isLoading: Bool = false

    private let types = ["checking", "savings", "credit", "cash", "brokerage", "other"]

    public init() {}

    public var body: some View {
        List {
            ForEach(accounts) { a in
                HStack {
                    VStack(alignment: .leading) {
                        Text(a.name).font(.headline)
                        Text(a.type).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((balances[a.id] ?? .zero).formatted())
                            .font(.body.monospacedDigit())
                            .foregroundStyle((balances[a.id] ?? .zero).cents >= 0
                                             ? Theme.incomeColor : Theme.spendingColor)
                        Text("balance").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(a.createdAt).font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if isLoading && accounts.isEmpty {
                ProgressView("Loading accounts…")
                    .padding(20)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Label("Add account", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingAdd) { addSheet }
        .refreshable {
            do {
                async let accounts = state.ledger.accounts()
                async let balances = state.ledger.accountBalances()
                let (rows, bals) = try await (accounts, balances)
                self.accounts = rows
                self.balances = bals
                self.isLoading = false
            } catch {
                state.lastError = "\(error)"
            }
        }
        .task { reload() }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $newType) {
                        ForEach(types, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("New account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = newName, type = newType
                        state.task({ _ = try await state.ledger.addAccount(name: name, type: type) })
                        { _ in
                            showingAdd = false; newName = ""; reload()
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func reload() {
        isLoading = true
        state.task({
            async let accounts = state.ledger.accounts()
            async let balances = state.ledger.accountBalances()
            return try await (accounts, balances)
        }) { (a, b) in
            self.accounts = a
            self.balances = b
            self.isLoading = false
        }
    }
}

#endif
