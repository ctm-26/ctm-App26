import SwiftUI
import SwiftData

struct AliasManagerView: View {
    let entity: Entity

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allAliases: [EntityAlias]

    @State private var newAliasText = ""
    @State private var validationError: String? = nil
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - Derived

    private var aliases: [EntityAlias] {
        allAliases
            .filter { $0.entityId == entity.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Alias list
                List {
                    if aliases.isEmpty {
                        Section {
                            Text("No aliases yet. Aliases let you find this entity by alternate names.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    } else {
                        Section {
                            ForEach(aliases) { alias in
                                HStack {
                                    Image(systemName: "at")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)

                                    Text(alias.alias)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text(DateUtils.relativeString(from: alias.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteAlias(alias)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Aliases for \"\(entity.canonicalName)\"")
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // Add alias input bar
                addAliasBar
            }
            .navigationTitle("Aliases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Add Alias Bar

    private var addAliasBar: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    TextField("New alias…", text: $newAliasText)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            addAlias()
                        }
                        .onChange(of: newAliasText) { _, _ in
                            validationError = nil
                        }

                    Button(action: addAlias) {
                        Text("Add")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                newAliasText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.secondary.opacity(0.2)
                                    : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .foregroundStyle(
                                newAliasText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.secondary
                                    : .white
                            )
                    }
                    .disabled(newAliasText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.plain)
                }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .animation(.easeInOut(duration: 0.18), value: validationError)
    }

    // MARK: - Actions

    private func addAlias() {
        let trimmed = newAliasText.trimmingCharacters(in: .whitespaces)

        // Basic validation
        let errors = Validation.validateAlias(alias: trimmed)
        if let firstError = errors.first {
            withAnimation { validationError = firstError }
            return
        }

        // Duplicate check (case-insensitive)
        let isDuplicate = aliases.contains {
            $0.alias.lowercased() == trimmed.lowercased()
        }
        if isDuplicate {
            withAnimation { validationError = "This alias already exists for this entity." }
            return
        }

        // Also check against canonical name
        if entity.canonicalName.lowercased() == trimmed.lowercased() {
            withAnimation { validationError = "Alias cannot be the same as the entity's canonical name." }
            return
        }

        let alias = EntityAlias(entityId: entity.id, alias: trimmed)
        modelContext.insert(alias)

        do {
            try modelContext.save()
            newAliasText = ""
            validationError = nil
            isTextFieldFocused = false
        } catch {
            withAnimation { validationError = "Failed to save: \(error.localizedDescription)" }
        }
    }

    private func deleteAlias(_ alias: EntityAlias) {
        modelContext.delete(alias)
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    let container = DatabaseController.previewContainer()
    let entity = Entity(entityType: .person, canonicalName: "Alice Smith")
    container.mainContext.insert(entity)

    let alias1 = EntityAlias(entityId: entity.id, alias: "Ali")
    let alias2 = EntityAlias(entityId: entity.id, alias: "Alice S.")
    container.mainContext.insert(alias1)
    container.mainContext.insert(alias2)

    return AliasManagerView(entity: entity)
        .modelContainer(container)
}
