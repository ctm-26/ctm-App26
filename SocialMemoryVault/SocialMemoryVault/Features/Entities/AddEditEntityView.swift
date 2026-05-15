import SwiftUI
import SwiftData

struct AddEditEntityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Editing mode when an entity is passed
    private let existingEntity: Entity?

    // MARK: - Form State

    @State private var canonicalName: String
    @State private var selectedType: EntityType
    @State private var notes: String
    @State private var validationErrors: [String] = []
    @State private var isSaving = false

    // MARK: - Init

    init(entity: Entity? = nil) {
        self.existingEntity = entity
        _canonicalName = State(initialValue: entity?.canonicalName ?? "")
        _selectedType = State(initialValue: entity?.entityTypeEnum ?? .person)
        _notes = State(initialValue: entity?.notes ?? "")
    }

    // MARK: - Computed

    private var isEditing: Bool { existingEntity != nil }
    private var title: String { isEditing ? "Edit Entity" : "New Entity" }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Name field
                Section {
                    TextField("Name", text: $canonicalName, axis: .vertical)
                        .font(.body)
                        .autocorrectionDisabled(false)
                        .onChange(of: canonicalName) { _, _ in
                            clearFieldError("Name")
                        }
                } header: {
                    Text("Name")
                } footer: {
                    if let nameError = validationErrors.first(where: { $0.contains("Name") }) {
                        Text(nameError)
                            .foregroundStyle(.red)
                    }
                }

                // Entity type picker
                Section("Type") {
                    Picker("Entity Type", selection: $selectedType) {
                        ForEach(EntityType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                // Notes field
                Section {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Optional notes about this entity…")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 90)
                    }
                } header: {
                    Text("Notes")
                }

                // Validation errors
                if !validationErrors.isEmpty {
                    Section {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(canonicalName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = canonicalName.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        let errors = Validation.validateEntity(
            canonicalName: trimmedName,
            entityType: selectedType.rawValue
        )

        guard errors.isEmpty else {
            validationErrors = errors
            return
        }

        validationErrors = []
        isSaving = true

        if let existing = existingEntity {
            // Update existing entity
            existing.canonicalName = trimmedName
            existing.entityType = selectedType.rawValue
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.updatedAt = Date()
        } else {
            // Create new entity
            let newEntity = Entity(
                entityType: selectedType,
                canonicalName: trimmedName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            modelContext.insert(newEntity)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationErrors = ["Failed to save: \(error.localizedDescription)"]
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func clearFieldError(_ keyword: String) {
        validationErrors.removeAll { $0.contains(keyword) }
    }
}

// MARK: - Preview

#Preview("New Entity") {
    AddEditEntityView()
        .modelContainer(DatabaseController.previewContainer())
}

#Preview("Edit Entity") {
    let container = DatabaseController.previewContainer()
    let entity = Entity(entityType: .person, canonicalName: "Alice Smith", notes: "Old friend from university.")
    container.mainContext.insert(entity)

    return AddEditEntityView(entity: entity)
        .modelContainer(container)
}
