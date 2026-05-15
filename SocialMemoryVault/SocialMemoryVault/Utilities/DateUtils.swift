import Foundation

struct DateUtils {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func isoString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func date(from isoString: String) -> Date? {
        isoFormatter.date(from: isoString)
    }

    static func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    static func displayDate(_ date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    static func relativeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
