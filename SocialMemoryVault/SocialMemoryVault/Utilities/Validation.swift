import Foundation

struct Validation {
    static func validateEntity(canonicalName: String, entityType: String) -> [String] {
        var errors: [String] = []
        if canonicalName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Name is required.")
        }
        if EntityType(rawValue: entityType) == nil {
            errors.append("Entity type is invalid.")
        }
        return errors
    }

    static func validateAlias(alias: String) -> [String] {
        var errors: [String] = []
        if alias.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Alias cannot be empty.")
        }
        return errors
    }

    static func validateMemory(body: String) -> [String] {
        var errors: [String] = []
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Memory body is required.")
        }
        return errors
    }

    static func validateClaim(subjectEntityId: String, predicate: String, objectEntityId: String?, value: String?) -> [String] {
        var errors: [String] = []
        if subjectEntityId.isEmpty {
            errors.append("Subject entity is required.")
        }
        if predicate.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Predicate is required.")
        }
        let hasObject = objectEntityId != nil && !objectEntityId!.isEmpty
        let hasValue = value != nil && !value!.trimmingCharacters(in: .whitespaces).isEmpty
        if !hasObject && !hasValue {
            errors.append("Either an object entity or a literal value is required.")
        }
        return errors
    }
}
