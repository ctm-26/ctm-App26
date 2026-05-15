import SwiftUI
import SwiftData

struct AddEditMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Modes
    private let existingMemory: Memory?
    /// When set, after saving the memory a MemoryEntityLink is created for this entity.
    private let initialEntityId: String?

    // MARK: - Form State
    @State private var body: String = ""
    @State private var summary: String = ""
    @State private var occurredAtEnabled: Bool = false
    @State private var occurredAt: Date = Date()
    @State private var privacyLevel: PrivacyLevel = .normal
    @State private var validationErrors: [String] = []
    @State private var showValidationAlert = false

    @AppStorage("defaultPrivacyLevel") private var defaultPrivacyLevelRaw: String = PrivacyLevel.normal.rawValue

    private var isEditing: Bool { existingMemory != nil }
    private var navTitle: String { isEditing ? "Edit Memory" : "New Memory" }

    // MARK: - Initializers

    /// Create a new memory, optionally linked to an entity after saving.
    init(initialEntityId: String? = nil) {
        self.existingMemory = nil
        self.initialEntityId = initialEntityId
    }

    /// Edit an existing memory.
    init(memory: Memory) {
        self.existingMemory = memory
        self.initialEntityId = nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Body
                Section {
                    ZStack(alignment: .topLeading) {
                        if self.body.isEmpty {
                            Text("What happened, what was said, what did you notice…")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $body)
                            .font(.body)
                            .frame(minHeight: 100)
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("Required. Write in your own words — the more detail, the better.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Summary
                Section {
                    TextField("Optional short title or summary", text: $summary)
                        .font(.subheadline)
                } header: {
                    Text("Summary")
                }

                // MARK: Occurred At
                Section {
                    Toggle("Set a date", isOn: $occurredAtEnabled.animation())

                    if occurredAtEnabled {
                        DatePicker(
                            "Occurred at",
                            selection: $occurredAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }
                } header: {
                    Text("When did this occur?")
                } footer: {
                    Text("Leave off if the exact date is unknown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Privacy
                Section {
                    Picker("Privacy Level", selection: $privacyLevel) {
                        ForEach(PrivacyLevel.allCases, id: \.self) { level in
                            Label(level.displayName, systemImage: level.systemImage)
                                .tag(level)
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    privacyFooter
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Cannot Save", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrors.joined(separator: "\n"))
            }
            .onAppear { prefill() }
        }
    }

    // MARK: - Privacy Footer

    @ViewBuilder
    private var privacyFooter: some View {
        switch privacyLevel {
        case .normal:
            Text("Included in standard exports.")
                .font(.caption).foregroundStyle(.secondary)
        case .sensitive:
            Text("Flagged as sensitive. Excluded from exports when \"Exclude Sensitive\" is on.")
                .font(.caption).foregroundStyle(.orange)
        case .doNotExport:
            Text("Never included in any export.")
                .font(.caption).foregroundStyle(.red)
        }
    }

    // MARK: - Logic

    private func prefill() {
        if let m = existingMemory {
            body = m.body
            summary = m.summary ?? ""
            privacyLevel = m.privacyLevelEnum
            if let oa = m.occurredAt {
                occurredAtEnabled = true
                occurredAt = oa
            }
        } else {
            // Apply default privacy from settings
            privacyLevel = PrivacyLevel(rawValue: defaultPrivacyLevelRaw) ?? .normal
        }
    }

    private func save() {
        let errors = Validation.validateMemory(body: body)
        guard errors.isEmpty else {
            validationErrors = errors
            showValidationAlert = true
            return
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = existingMemory {
            // Edit mode
            existing.body = trimmedBody
            existing.summary = trimmedSummary.isEmpty ? nil : trimmedSummary
            existing.occurredAt = occurredAtEnabled ? occurredAt : nil
            existing.privacyLevel = privacyLevel.rawValue
            existing.updatedAt = Date()
        } else {
            // Create mode
            let newMemory = Memory(
                body: trimmedBody,
                summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                occurredAt: occurredAtEnabled ? occurredAt : nil,
                privacyLevel: privacyLevel
            )
            modelContext.insert(newMemory)

            // If launched from an entity context, auto-link
            if let entityId = initialEntityId {
                let link = MemoryEntityLink(
                    memoryId: newMemory.id,
                    entityId: entityId,
                    role: .participant
                )
                modelContext.insert(link)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview("New") {
    AddEditMemoryView()
        .modelContainer(DatabaseController.previewContainer())
}

#Preview("Edit") {
    AddEditMemoryView(memory: Memory(
        body: "Ran into Sarah at the farmers market. She mentioned moving to Portland.",
        summary: "Sarah moving to Portland",
        privacyLevel: .normal
    ))
    .modelContainer(DatabaseController.previewContainer())
}
