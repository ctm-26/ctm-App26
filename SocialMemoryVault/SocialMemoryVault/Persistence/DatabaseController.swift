import Foundation
import SwiftData

@MainActor
class DatabaseController {
    static let shared = DatabaseController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            Entity.self,
            EntityAlias.self,
            Memory.self,
            MemoryEntityLink.self,
            Claim.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    static func previewContainer() -> ModelContainer {
        let schema = Schema([
            Entity.self,
            EntityAlias.self,
            Memory.self,
            MemoryEntityLink.self,
            Claim.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }
}
