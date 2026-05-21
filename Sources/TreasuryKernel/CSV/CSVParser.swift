import Foundation

/// RFC 4180-ish CSV parser. Handles quoted fields, embedded commas, "" escapes,
/// CRLF or LF line endings.
public struct CSVParser {
    public let text: String

    public init(text: String) { self.text = text }

    public init(data: Data, encoding: String.Encoding = .utf8) throws {
        guard let s = String(data: data, encoding: encoding) else {
            throw TreasuryError.io("could not decode CSV as \(encoding)")
        }
        self.text = s
    }

    public func rows() -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var current: [String] = []
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = next
                        continue
                    }
                } else {
                    field.append(c)
                    i = text.index(after: i)
                    continue
                }
            }
            switch c {
            case "\"":
                inQuotes = true
                i = text.index(after: i)
            case ",":
                current.append(field); field = ""
                i = text.index(after: i)
            case "\r":
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "\n" {
                    i = text.index(after: next)
                } else {
                    i = next
                }
                current.append(field); field = ""
                if !(current.count == 1 && current[0].isEmpty) { rows.append(current) }
                current = []
            case "\n":
                current.append(field); field = ""
                if !(current.count == 1 && current[0].isEmpty) { rows.append(current) }
                current = []
                i = text.index(after: i)
            default:
                field.append(c)
                i = text.index(after: i)
            }
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            if !(current.count == 1 && current[0].isEmpty) { rows.append(current) }
        }
        return rows
    }
}

/// Header detection mirrors the C kernel's importer.
public struct CSVHeaderMap {
    public let date: Int
    public let description: Int
    public let amount: Int?
    public let debit: Int?
    public let credit: Int?

    public static func detect(from header: [String]) -> CSVHeaderMap? {
        var date: Int?; var desc: Int?; var amount: Int?; var debit: Int?; var credit: Int?
        for (i, raw) in header.enumerated() {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch key {
            case "date", "transaction date", "posting date", "post date", "trans date":
                if date == nil { date = i }
            case "description", "name", "memo", "payee", "details":
                if desc == nil { desc = i }
            case "amount":
                if amount == nil { amount = i }
            case "debit", "withdrawal":
                if debit == nil { debit = i }
            case "credit", "deposit":
                if credit == nil { credit = i }
            default:
                continue
            }
        }
        guard let d = date, let de = desc else { return nil }
        guard amount != nil || debit != nil || credit != nil else { return nil }
        return CSVHeaderMap(date: d, description: de, amount: amount,
                            debit: debit, credit: credit)
    }
}
