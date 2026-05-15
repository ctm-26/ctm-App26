import Foundation
import SwiftData

enum EntityType: String, CaseIterable, Codable {
    case person
    case place
    case organization
    case concept
    case object
    case event
    case unknown

    var displayName: String {
        switch self {
        case .person: return "Person"
        case .place: return "Place"
        case .organization: return "Organization"
        case .concept: return "Concept"
        case .object: return "Object"
        case .event: return "Event"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .organization: return "building.2.fill"
        case .concept: return "lightbulb.fill"
        case .object: return "cube.fill"
        case .event: return "calendar"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

@Model
final class Entity {
    var id: String
    var entityType: String
    var canonicalName: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: String = IDGenerator.newID(),
         entityType: EntityType,
         canonicalName: String,
         notes: String? = nil) {
        self.id = id
        self.entityType = entityType.rawValue
        self.canonicalName = canonicalName
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var entityTypeEnum: EntityType {
        EntityType(rawValue: entityType) ?? .unknown
    }
}
