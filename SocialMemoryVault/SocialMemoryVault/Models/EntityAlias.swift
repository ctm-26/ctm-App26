import Foundation
import SwiftData

@Model
final class EntityAlias {
    var id: String
    var entityId: String
    var alias: String
    var createdAt: Date

    init(id: String = IDGenerator.newID(),
         entityId: String,
         alias: String) {
        self.id = id
        self.entityId = entityId
        self.alias = alias
        self.createdAt = Date()
    }
}
