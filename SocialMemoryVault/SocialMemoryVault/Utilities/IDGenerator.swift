import Foundation

struct IDGenerator {
    static func newID() -> String {
        UUID().uuidString
    }
}
