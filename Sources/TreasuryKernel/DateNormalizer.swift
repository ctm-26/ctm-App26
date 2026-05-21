import Foundation

/// Match the C kernel's `util_normalize_date`. Accepts:
///   YYYY-MM-DD, YYYY/MM/DD, MM/DD/YYYY, MM-DD-YYYY, M/D/YY, M/D/YYYY.
public enum DateNormalizer {
    public static func normalize(_ raw: String) -> String? {
        let s = raw.filter { !$0.isWhitespace }
        guard !s.isEmpty else { return nil }

        if let m = matchYMD(s, sep: "-") { return iso(y: m.0, m: m.1, d: m.2) }
        if let m = matchYMD(s, sep: "/") { return iso(y: m.0, m: m.1, d: m.2) }
        if let m = matchMDY(s, sep: "/") { return iso(y: m.0, m: m.1, d: m.2) }
        if let m = matchMDY(s, sep: "-") { return iso(y: m.0, m: m.1, d: m.2) }
        return nil
    }

    public static func validYearMonth(_ s: String) -> Bool {
        guard s.count == 7 else { return false }
        let parts = s.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return y >= 1900 && y <= 2999 && m >= 1 && m <= 12
    }

    private static func iso(y: Int, m: Int, d: Int) -> String? {
        guard validYMD(y: y, m: m, d: d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func matchYMD(_ s: String, sep: Character) -> (Int, Int, Int)? {
        let parts = s.split(separator: sep)
        guard parts.count == 3, parts[0].count == 4 else { return nil }
        guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return (y, m, d)
    }

    private static func matchMDY(_ s: String, sep: Character) -> (Int, Int, Int)? {
        let parts = s.split(separator: sep)
        guard parts.count == 3 else { return nil }
        guard let m = Int(parts[0]), let d = Int(parts[1]), var y = Int(parts[2]) else { return nil }
        if y < 100 { y += (y < 70 ? 2000 : 1900) }
        return (y, m, d)
    }

    private static func validYMD(y: Int, m: Int, d: Int) -> Bool {
        guard y >= 1900, y <= 2999, m >= 1, m <= 12, d >= 1 else { return false }
        let dim: [Int] = [31, isLeap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return d <= dim[m - 1]
    }

    private static func isLeap(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
    }
}
