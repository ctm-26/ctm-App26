import Foundation
import SwiftData

enum LinkRole: String, CaseIterable, Codable {
    case subject
    case participant
    case topic
    case location
    case object
    case mentioned
    case unknown

    var displayName: String {
        switch self {
        case .subject: return "Subject"
        case .participant: return "Participant"
        case .topic: return "Topic"
        case .location: return "Location"
        case .object: return "Object"
        case .mentioned: return "Mentioned"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .subject: return "person.fill"
        case .participant: return "person.2.fill"
        case .topic: return "tag.fill"
        case .location: return "mappin.fill"
        case .object: return "cube.fill"
        case .mentioned: return "quote.bubble.fill"
        case .unknown: return "questionmark"
        }
    }
}

@Model
final class MemoryEntityLink {
    var id: String
    var memoryId: String
    var entityId: String
    var role: String
    var createdAt: Date

    init(id: String = IDGenerator.newID(),
         memoryId: String,
         entityId: String,
         role: LinkRole) {
        self.id = id
        self.memoryId = memoryId
        self.entityId = entityId
        self.role = role.rawValue
        self.createdAt = Date()
    }

    var roleEnum: LinkRole {
        LinkRole(rawValue: role) ?? .unknown
    }
}
