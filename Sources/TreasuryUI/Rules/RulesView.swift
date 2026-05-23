import SwiftUI
import TreasuryKernel

#if canImport(UIKit)

public struct RulesView: View {
    @Environment(AppState.self) private var state
    @State private var rules: [Rule] = []
    @State private var showAdd = false
    @State private var isLoading: Bool = false

    @State private var newPattern = ""
    @State private var newCategory = ""
    @State private var newPriority = 100

    public init() {}

    public var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(rules) { r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.pattern).font(.body.monospaced())
                            Text("→ \(r.categoryName)  ·  pri \(r.priority)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            state.task({ try await state.rules.removeRule(id: r.id) }) { _ in reload() }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete rule")
                    }
                }
            }
        }
        .overlay {
            if isLoading && rules.isEmpty {
                ProgressView("Loading rules…")
                    .padding(20)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Add", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    state.task({ try await state.rules.classifyAll() }) { _ in reload() }
                } label: { Label("Classify", systemImage: "wand.and.rays") }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .task { reload() }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Match (case-insensitive substring)") {
                    TextField("Pattern (e.g. SHOPRITE)", text: $newPattern)
                        .textInputAutocapitalization(.characters)
                }
                Section("Action") {
                    TextField("Category", text: $newCategory)
                    Stepper("Priority: \(newPriority)", value: $newPriority, in: 1...999)
                }
                Section {
                    Text("Lower priority numbers win first. Same value? First created wins.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let p = newPattern, c = newCategory, pri = newPriority
                        state.task({
                            _ = try await state.rules.addRule(pattern: p, categoryName: c, priority: pri)
                        }) { _ in
                            showAdd = false
                            newPattern = ""; newCategory = ""; newPriority = 100
                            reload()
                        }
                    }
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty
                              || newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func reload() {
        isLoading = true
        state.task({ try await state.rules.rules() }) { rows in
            self.rules = rows
            self.isLoading = false
        }
    }
}

#endif
