import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var memories: [Memory]

    @State private var showAddEntity = false
    @State private var showAddClaim = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if memories.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome to Social Memory Vault")
                                .font(.headline)
                            Text("Start by adding an entity or a memory.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section("Recent Memories") {
                        ForEach(memories) { memory in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.body)
                                    .font(.body)
                                    .lineLimit(3)
                                Text(DateUtils.display(memory.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Entity") { showAddEntity = true }
                        Button("Add Claim") { showAddClaim = true }
                        Button("Add Memory") { addSampleMemory() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddEntity) {
                AddEditEntityView()
            }
            .sheet(isPresented: $showAddClaim) {
                AddEditClaimView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private func addSampleMemory() {
        let mem = Memory(body: "Sample memory")
        modelContext.insert(mem)
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(DatabaseController.previewContainer())
}
