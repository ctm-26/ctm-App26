import SwiftUI

struct ExportImportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Export") {
                    Button("Export to JSON") {
                        // Placeholder
                    }
                }
                Section("Import") {
                    Button("Import from JSON") {
                        // Placeholder
                    }
                }
            }
            .navigationTitle("Export / Import")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ExportImportView()
}
