import SwiftUI
import SwiftData

@main
struct SocialMemoryVaultApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Entity.self,
            EntityAlias.self,
            Memory.self,
            MemoryEntityLink.self,
            Claim.self
        ])
    }
}
