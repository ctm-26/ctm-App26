import Foundation
import SwiftData

@Model
final class Claim {
    var id: String
    var subjectEntityId: String
    var predicate: String
    var objectEntityId: String?
    var value: String?
    var memoryId: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: String = IDGenerator.newID(),
         subjectEntityId: String,
         predicate: String,
         objectEntityId: String? = nil,
         value: String? = nil,
         memoryId: String? = nil) {
        self.id = id
        self.subjectEntityId = subjectEntityId
        self.predicate = predicate
        self.objectEntityId = objectEntityId
        self.value = value
        self.memoryId = memoryId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isValid: Bool {
        !subjectEntityId.isEmpty && !predicate.isEmpty && (objectEntityId != nil || (value != nil && !(value!.isEmpty)))
    }
}
