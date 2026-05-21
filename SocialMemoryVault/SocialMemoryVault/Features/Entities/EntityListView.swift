import SwiftUI
import SwiftData

struct EntityListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Entity.canonicalName, order: .forward)
    private var allEntities: [Entity]

    @Query private var allLinks: [MemoryEntityLink]

    @State private var selectedType: EntityType? = nil  // nil = "All"
    @State private var sortOrder: EntitySortOrder = .name
    @State private var showAddEntity = false
    @State private var entityToDelete: Entity? = nil
    @State private var showDeleteConfirmation = false

    // MARK: - Filtered & Sorted

    private var filteredEntities: [Entity] {
        let base: [Entity]
        if let type = selectedType {
            base = allEntities.filter { $0.entityTypeEnum == type }
        } else {
            base = allEntities
        }

        switch sortOrder {
        case .name:
            return base.sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
        case .recentlyMentioned:
            return base.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if allEntities.isEmpty {
                emptyStateView
            } else {
                listContent
            }
        }
        .navigationTitle("Entities")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddEntity = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Entity")
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(EntitySortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Sort Options")
            }
        }
        .sheet(isPresented: $showAddEntity) {
            AddEditEntityView()
        }
        .confirmationDialog(
            "Delete \"\(entityToDelete?.canonicalName ?? "Entity")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entity = entityToDelete {
                    deleteEntity(entity)
                }
                entityToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                entityToDelete = nil
            }
        } message: {
            Text("This will also remove all aliases and memory links for this entity.")
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            // Type filter segmented control
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TypeFilterChip(label: "All", isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(EntityType.allCases, id: \.self) { type in
                            TypeFilterChip(
                                label: type.displayName,
                                systemImage: type.systemImage,
                                isSelected: selectedType == type
                            ) {
                                selectedType = (selectedType == type) ? nil : type
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)

            if filteredEntities.isEmpty {
                Section {
                    Text("No entities match the selected filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredEntities) { entity in
                        NavigationLink(value: entity) {
                            EntityListRow(entity: entity, memoryCount: memoryCount(for: entity))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entityToDelete = entity
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Entity.self) { entity in
            EntityDetailView(entity: entity)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Entities Yet")
                    .font(.title3.weight(.semibold))
                Text("Entities are people, places, organizations, and concepts connected to your memories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showAddEntity = true
            } label: {
                Label("Add Entity", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddEntity) {
            AddEditEntityView()
        }
    }

    // MARK: - Helpers

    private func memoryCount(for entity: Entity) -> Int {
        allLinks.filter { $0.entityId == entity.id }.count
    }

    private func deleteEntity(_ entity: Entity) {
        // Delete aliases
        let aliasesFetch = FetchDescriptor<EntityAlias>(
            predicate: #Predicate { $0.entityId == entity.id }
        )
        let aliases = (try? modelContext.fetch(aliasesFetch)) ?? []
        aliases.forEach { modelContext.delete($0) }

        // Delete memory links
        let linksFetch = FetchDescriptor<MemoryEntityLink>(
            predicate: #Predicate { $0.entityId == entity.id }
        )
        let links = (try? modelContext.fetch(linksFetch)) ?? []
        links.forEach { modelContext.delete($0) }

        // Delete the entity itself
        modelContext.delete(entity)
        try? modelContext.save()
    }
}

// MARK: - Entity List Row

private struct EntityListRow: View {
    let entity: Entity
    let memoryCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: entity.entityTypeEnum.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entity.entityTypeEnum))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entity.canonicalName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(entity.entityTypeEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if memoryCount > 0 {
                Text("\(memoryCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Type Filter Chip

private struct TypeFilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let img = systemImage {
                    Image(systemName: img)
                        .font(.caption2.weight(.semibold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Order

enum EntitySortOrder: String, CaseIterable, Identifiable {
    case name
    case recentlyMentioned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name (A–Z)"
        case .recentlyMentioned: return "Recently Added"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EntityListView()
    }
    .modelContainer(DatabaseController.previewContainer())
}
