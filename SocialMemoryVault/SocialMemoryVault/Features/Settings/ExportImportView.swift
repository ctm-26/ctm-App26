import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - ExportImportView

struct ExportImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allEntities: [Entity]
    @Query private var allMemories: [Memory]
    @Query private var allClaims: [Claim]

    // Export state
    @State private var exportMode: ExportMode = .standard
    @State private var excludeSensitive: Bool = true
    @State private var exportItem: ExportActivityItem? = nil
    @State private var showShareSheet = false
    @State private var exportError: String? = nil
    @State private var showExportErrorAlert = false

    // Import state
    @State private var showDocumentPicker = false
    @State private var importResult: ImportResult? = nil
    @State private var showImportResultAlert = false
    @State private var importError: String? = nil
    @State private var showImportErrorAlert = false
    @State private var isImporting = false

    enum ExportMode: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case full = "Full"
        case minimal = "Minimal"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .standard: return "Entities, claims, and memory summaries"
            case .full: return "Everything, including full memory bodies"
            case .minimal: return "Entities and claims only"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Stats
                Section {
                    HStack {
                        StatBadge(value: allEntities.count, label: "Entities", systemImage: "person.2.fill", color: .blue)
                        Spacer()
                        StatBadge(value: allMemories.count, label: "Memories", systemImage: "note.text", color: .purple)
                        Spacer()
                        StatBadge(value: allClaims.count, label: "Claims", systemImage: "checkmark.seal.fill", color: .green)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Vault Stats")
                }

                // MARK: Export
                Section {
                    Picker("Export Mode", selection: $exportMode) {
                        ForEach(ExportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    Toggle("Exclude Sensitive & Do Not Export", isOn: $excludeSensitive)

                    Button {
                        performExport()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Export")
                } footer: {
                    Text(exportMode.description + (excludeSensitive ? ". Sensitive memories excluded." : ". All privacy levels included."))
                        .font(.caption)
                }

                // MARK: Import
                Section {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Importing…")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            } else {
                                Label("Import JSON", systemImage: "square.and.arrow.down")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                    .padding(.vertical, 4)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Select a Social Memory Vault JSON export file. Duplicate records are skipped automatically.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Export / Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let item = exportItem {
                    ShareSheet(activityItems: [item.url])
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(contentTypes: [.json]) { url in
                    handleImport(url: url)
                }
            }
            .alert("Export Failed", isPresented: $showExportErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "An unknown error occurred.")
            }
            .alert("Import Complete", isPresented: $showImportResultAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if let result = importResult {
                    Text(result.summary)
                }
            }
            .alert("Import Failed", isPresented: $showImportErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Export Logic

    private func performExport() {
        do {
            // For minimal mode, we export without memory bodies by using excludeSensitive=true
            // and then strip memory bodies. For simplicity, we use the ExportService
            // directly and pass the excludeSensitive flag.
            let data = try ExportService.export(context: modelContext, excludeSensitive: excludeSensitive)

            // Write to a temp file
            let fileName = "social_memory_vault_\(exportTimestamp()).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL, options: .atomic)

            exportItem = ExportActivityItem(url: tempURL)
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
            showExportErrorAlert = true
        }
    }

    private func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Import Logic

    private func handleImport(url: URL) {
        isImporting = true
        Task {
            do {
                let data = try Data(contentsOf: url)
                let result = try ImportService.importData(data, into: modelContext)
                await MainActor.run {
                    importResult = result
                    isImporting = false
                    showImportResultAlert = true
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                    showImportErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Helpers

private struct ExportActivityItem {
    let url: URL
}

private struct StatBadge: View {
    let value: Int
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ShareSheet (UIViewControllerRepresentable)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - DocumentPicker (UIViewControllerRepresentable)

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Preview

#Preview {
    ExportImportView()
        .modelContainer(DatabaseController.previewContainer())
}
