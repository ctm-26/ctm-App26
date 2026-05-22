import SwiftUI
import TreasuryKernel
import UniformTypeIdentifiers

public struct ImportView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    public let accounts: [Account]
    public let onComplete: () -> Void

    @State private var selectedAccount: Account?
    @State private var pickerPresented = false
    @State private var fileURL: URL?
    @State private var dryRun = true
    @State private var preview: ImportResult?
    @State private var running = false
    @State private var importSuccessTrigger: Int = 0

    public init(accounts: [Account], onComplete: @escaping () -> Void) {
        self.accounts = accounts; self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select").tag(nil as Account?)
                        ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                    }
                    HStack {
                        Text("File")
                        Spacer()
                        if let url = fileURL {
                            Text(url.lastPathComponent).foregroundStyle(.secondary)
                        } else {
                            Text("none").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        pickerPresented = true
                    } label: {
                        Label(fileURL == nil ? "Choose CSV" : "Choose another",
                              systemImage: "doc")
                    }
                }
                Section("Options") {
                    Toggle("Dry run (preview only)", isOn: $dryRun)
                }
                if let p = preview {
                    Section("Result") {
                        labeled("Total rows", "\(p.totalRows)")
                        labeled("Imported", "\(p.inserted)")
                        labeled("Duplicates", "\(p.duplicates)")
                        labeled("Rejected", "\(p.rejected)")
                        if !p.rejectedReasons.isEmpty {
                            DisclosureGroup("Rejected reasons") {
                                ForEach(p.rejectedReasons, id: \.self) {
                                    Text($0).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(dryRun ? "Preview" : "Import") { run() }
                        .disabled(selectedAccount == nil || fileURL == nil || running)
                }
            }
            .fileImporter(isPresented: $pickerPresented,
                          allowedContentTypes: [.commaSeparatedText, .text]) { result in
                if case .success(let url) = result { fileURL = url }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: importSuccessTrigger)
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).monospacedDigit() }
    }

    private func run() {
        guard let account = selectedAccount, let url = fileURL else { return }
        running = true
        state.task({
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            let csv = try String(contentsOf: url, encoding: .utf8)
            return try await state.importer.importCSV(csv,
                                                      sourceName: url.lastPathComponent,
                                                      accountName: account.name,
                                                      dryRun: dryRun)
        }) { result in
            preview = result
            running = false
            if !dryRun, result.inserted > 0 {
                importSuccessTrigger &+= 1
                onComplete()
                dismiss()
            }
        }
    }
}
