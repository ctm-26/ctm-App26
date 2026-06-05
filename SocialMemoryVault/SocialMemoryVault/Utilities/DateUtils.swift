import Foundation

enum DateUtils {
    static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    static func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}
