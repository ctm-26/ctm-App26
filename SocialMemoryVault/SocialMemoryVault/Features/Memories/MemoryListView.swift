import SwiftUI
import SwiftData

struct MemoryListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Memory.createdAt, order: .reverse)
    private var allMemories: [Memory]

    @Query private var allLinks: [MemoryEntityLink]

    @State private var showAddMemory = false
    @State private var privacyFilter: PrivacyFilter = .all

    enum PrivacyFilter: String, CaseIterable {
        case all = "All"
        case normal = "Normal"
        case sensitive = "Sensitive"

        func matches(_ memory: Memory) -> Bool {
            switch self {
            case .all: return true
            case .normal: return memory.privacyLevel == PrivacyLevel.normal.rawValue
            case .sensitive:
                return memory.privacyLevel == PrivacyLevel.sensitive.rawValue
                    || memory.privacyLevel == PrivacyLevel.doNotExport.rawValue
            }
        }
    }

    private var filteredMemories: [Memory] {
        allMemories.filter { privacyFilter.matches($0) }
    }

    var body: some View {
        Group {
            if allMemories.isEmpty {
                emptyStateView
            } else {
                listContent
            }
        }
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddMemory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Memory")
            }
        }
        .sheet(isPresented: $showAddMemory) {
            AddEditMemoryView()
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            // Filter picker
            Section {
                Picker("Filter", selection: $privacyFilter) {
                    ForEach(PrivacyFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)

            if filteredMemories.isEmpty {
                Section {
                    Text("No memories match this filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredMemories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryListRow(memory: memory, entityCount: entityCount(for: memory))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteMemory(memory)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Memories Yet")
                    .font(.title3.weight(.semibold))
                Text("Record conversations, observations, and facts about the people and places in your life.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showAddMemory = true
            } label: {
                Label("Add Memory", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddMemory) {
            AddEditMemoryView()
        }
    }

    // MARK: - Helpers

    private func entityCount(for memory: Memory) -> Int {
        allLinks.filter { $0.memoryId == memory.id }.count
    }

    private func deleteMemory(_ memory: Memory) {
        MemoryService.delete(memory, in: modelContext)
        try? modelContext.save()
    }
}

// MARK: - Memory List Row

private struct MemoryListRow: View {
    let memory: Memory
    let entityCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.body)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(DateUtils.relativeString(from: memory.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Privacy icon (only for non-normal)
                let level = memory.privacyLevelEnum
                if level != .normal {
                    Image(systemName: level.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(level == .doNotExport ? .red : .orange)
                }

                // Entity count badge
                if entityCount > 0 {
                    Label("\(entityCount)", systemImage: "person.2.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MemoryListView()
    }
    .modelContainer(DatabaseController.previewContainer())
}
