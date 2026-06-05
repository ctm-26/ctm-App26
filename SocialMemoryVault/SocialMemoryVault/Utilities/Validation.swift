import Foundation

struct Validation {
    static func validateEntity(canonicalName: String, entityType: String) -> [String] {
        var errors: [String] = []
        if canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name is required.")
        }
        if EntityType(rawValue: entityType) == nil {
            errors.append("Invalid entity type.")
        }
        return errors
    }

    static func validateClaim(subjectEntityId: String, predicate: String, objectEntityId: String?, value: String?) -> [String] {
        var errors: [String] = []
        if subjectEntityId.isEmpty { errors.append("Subject entity is required.") }
        if predicate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Predicate is required.") }
        if objectEntityId == nil && (value == nil || value?.isEmpty == true) {
            errors.append("Provide either an object entity or a literal value.")
        }
        return errors
    }
}
