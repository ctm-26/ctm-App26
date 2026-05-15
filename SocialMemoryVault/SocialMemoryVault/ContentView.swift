import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            // MARK: Home
            NavigationStack {
                HomeView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("Settings", systemImage: "gear")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            // MARK: Entities
            NavigationStack {
                EntityListView()
            }
            .tabItem {
                Label("Entities", systemImage: "person.3.fill")
            }

            // MARK: Memories
            NavigationStack {
                MemoryListView()
            }
            .tabItem {
                Label("Memories", systemImage: "note.text")
            }

            // MARK: Search
            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Entity.self,
            EntityAlias.self,
            Memory.self,
            MemoryEntityLink.self,
            Claim.self
        ], inMemory: true)
}
