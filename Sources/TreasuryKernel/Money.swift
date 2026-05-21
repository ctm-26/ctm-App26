import Foundation

/// Integer cents. Zero floating point in the ledger path; the same rule the
/// C kernel enforces.
public struct Money: Equatable, Hashable, Codable, Sendable {
    public let cents: Int64

    public init(cents: Int64) { self.cents = cents }

    public static let zero = Money(cents: 0)

    public var doubleValue: Double { Double(cents) / 100.0 }

    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static prefix func - (a: Money) -> Money { Money(cents: -a.cents) }

    /// Parse "$1,234.56", "(42.18)", "-12.5" etc into integer cents.
    /// Returns nil on parse failure.
    public static func parse(_ s: String) -> Money? {
        var negative = false
        var sawDigit = false
        var inDecimal = false
        var decimals = 0
        var digits = ""
        for ch in s {
            if ch.isWhitespace || ch == "$" || ch == "," { continue }
            if ch == "(" { negative = true; continue }
            if ch == ")" { continue }
            if ch == "+" { continue }
            if ch == "-" { negative.toggle(); continue }
            if ch == "." {
                if inDecimal { return nil }
                inDecimal = true
                continue
            }
            guard ch.isASCII, ch.isNumber else { return nil }
            digits.append(ch)
            sawDigit = true
            if inDecimal {
                decimals += 1
                if decimals > 2 { return nil }
            }
        }
        guard sawDigit else { return nil }
        while decimals < 2 { digits.append("0"); decimals += 1 }
        guard let v = Int64(digits) else { return nil }
        return Money(cents: negative ? -v : v)
    }

    /// "1234.56" / "-42.18"
    public var plainString: String {
        let neg = cents < 0
        let abs = UInt64(neg ? -(cents &+ 1) : cents) &+ (neg ? 1 : 0)
        let whole = abs / 100
        let frac = abs % 100
        return "\(neg ? "-" : "")\(whole).\(String(format: "%02llu", frac))"
    }

    /// Locale-aware currency formatting; falls back to plainString.
    public func formatted(currencyCode: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: doubleValue)) ?? plainString
    }
}
