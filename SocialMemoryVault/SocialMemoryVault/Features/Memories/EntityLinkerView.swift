import SwiftUI
import SwiftData

struct EntityLinkerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let memory: Memory

    @State private var links: [MemoryEntityLink] = []
    @State private var searchText: String = ""
    @State private var searchResults: [Entity] = []
    @State private var selectedEntity: Entity? = nil
    @State private var selectedRole: LinkRole = .participant
    @State private var showAddEntity = false
    @State private var showRolePicker = false

    var body: some View {
        NavigationStack {
            List {
                // Memory context header
                Section {
                    Text(memory.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.vertical, 4)
                } header: {
                    Text("Memory")
                }

                // Current links
                Section {
                    if links.isEmpty {
                        Text("No entities linked yet.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(links) { link in
                            let entity = EntityResolutionService.findEntity(byId: link.entityId, in: modelContext)
                            CurrentLinkRow(
                                entityName: entity?.canonicalName ?? "Unknown",
                                entityType: entity?.entityTypeEnum ?? .unknown,
                                role: link.roleEnum
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeLink(link)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Linked Entities")
                }

                // Search
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        TextField("Search entities by name…", text: $searchText)
                            .autocorrectionDisabled()
                            .onChange(of: searchText) { _, newValue in
                                performSearch(newValue)
                            }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Add Link")
                }

                // Search results
                if !searchResults.isEmpty {
                    Section {
                        ForEach(searchResults) { entity in
                            let alreadyLinked = links.contains { $0.entityId == entity.id }
                            Button {
                                selectedEntity = entity
                                selectedRole = .participant
                                showRolePicker = true
                            } label: {
                                SearchResultRow(entity: entity, alreadyLinked: alreadyLinked)
                            }
                            .disabled(alreadyLinked)
                        }
                    } header: {
                        Text("Results")
                    }
                } else if !searchText.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No entities found for \"\(searchText)\".")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                showAddEntity = true
                            } label: {
                                Label("Create New Entity", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Create new entity button (always visible)
                Section {
                    Button {
                        showAddEntity = true
                    } label: {
                        Label("Create New Entity", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Link Entities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAddEntity, onDismiss: { reloadLinks() }) {
                AddEditEntityView()
            }
            .sheet(isPresented: $showRolePicker) {
                rolePicker
            }
            .onAppear { reloadLinks() }
        }
    }

    // MARK: - Role Picker Sheet

    private var rolePicker: some View {
        NavigationStack {
            List {
                if let entity = selectedEntity {
                    Section {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: entity.entityTypeEnum.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(entityTypeColor(entity.entityTypeEnum))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entity.canonicalName)
                                    .font(.subheadline.weight(.medium))
                                Text(entity.entityTypeEnum.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Entity")
                    }
                }

                Section {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(LinkRole.allCases.filter { $0 != .unknown }, id: \.self) { role in
                            Label(role.displayName, systemImage: role.systemImage).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Choose Role")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Link Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRolePicker = false
                        selectedEntity = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Link") {
                        if let entity = selectedEntity {
                            addLink(entity: entity, role: selectedRole)
                        }
                        showRolePicker = false
                        selectedEntity = nil
                        searchText = ""
                        searchResults = []
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedEntity == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func performSearch(_ text: String) {
        guard !text.isEmpty else {
            searchResults = []
            return
        }
        searchResults = EntityResolutionService.findMatches(for: text, in: modelContext)
    }

    private func reloadLinks() {
        links = MemoryService.fetchLinks(for: memory.id, in: modelContext)
    }

    private func addLink(entity: Entity, role: LinkRole) {
        // Prevent duplicates
        guard !links.contains(where: { $0.entityId == entity.id }) else { return }
        let link = MemoryEntityLink(
            memoryId: memory.id,
            entityId: entity.id,
            role: role
        )
        modelContext.insert(link)
        try? modelContext.save()
        reloadLinks()
    }

    private func removeLink(_ link: MemoryEntityLink) {
        modelContext.delete(link)
        try? modelContext.save()
        reloadLinks()
    }
}

// MARK: - Sub-views

private struct CurrentLinkRow: View {
    let entityName: String
    let entityType: EntityType
    let role: LinkRole

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entityType).opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: entityType.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entityType))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entityName)
                    .font(.subheadline.weight(.medium))
                Label(role.displayName, systemImage: role.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SearchResultRow: View {
    let entity: Entity
    let alreadyLinked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(alreadyLinked ? 0.07 : 0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: entity.entityTypeEnum.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entity.entityTypeEnum).opacity(alreadyLinked ? 0.4 : 1))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.canonicalName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(alreadyLinked ? .secondary : .primary)
                Text(entity.entityTypeEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if alreadyLinked {
                Text("Linked")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    EntityLinkerView(memory: Memory(
        body: "Had coffee with Jordan and we talked about the new project at Meridian Tech.",
        privacyLevel: .normal
    ))
    .modelContainer(DatabaseController.previewContainer())
}
