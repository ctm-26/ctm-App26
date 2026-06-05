import Foundation
import SwiftData

enum DatabaseController {
    @MainActor
    static func previewContainer() -> ModelContainer {
        let schema = Schema([Entity.self, EntityAlias.self, Memory.self, MemoryEntityLink.self, Claim.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Force-try for previews
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
