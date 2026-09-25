import Foundation

/// Reads a number the user typed, in their own locale.
///
/// A plain `Double(text)` only understands a point, and swapping every comma
/// for a point turns an English "1,500" into 1.5. This reads the locale's
/// separators instead, and stays lenient about the other one where the text is
/// unambiguous: a separator is taken as grouping only when it is the locale's
/// grouping separator and the digits after it form whole groups, so "1.5" is
/// 1.5 even in Germany while "1.500" there is 1500.
///
/// Pasted recipe text goes through `RecipeTextNumbers` instead — that is
/// foreign text, not the user's own input.
enum LocaleDecimal {
    /// Whether a numeric field's text can be saved: empty, or a number. A form
    /// must refuse to save anything else rather than store it as nothing.
    static func isReadable(_ text: String, locale: Locale = .autoupdatingCurrent) -> Bool {
        text.allSatisfy(\.isWhitespace) || parse(text, locale: locale) != nil
    }

    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let groupingSeparator = locale.groupingSeparator ?? ","
        var compact = text.filter { !$0.isWhitespace }
        if groupingSeparator != ".", groupingSeparator != "," {
            compact = compact.replacingOccurrences(of: groupingSeparator, with: "")
        }
        let isNegative = compact.first == "-" || compact.first == "\u{2212}"
        if isNegative {
            compact.removeFirst()
        }
        return magnitude(compact, groupingSeparator: groupingSeparator)
            .map { isNegative ? -$0 : $0 }
    }

    private static func magnitude(_ compact: String, groupingSeparator: String) -> Double? {
        guard !compact.isEmpty, compact.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," }) else {
            return nil
        }

        let separators = Set(compact.filter { $0 == "." || $0 == "," })
        guard let lastSeparator = compact.last(where: { $0 == "." || $0 == "," }) else {
            return Double(compact)
        }
        if separators.count == 2 {
            return number(compact, decimal: lastSeparator)
        }
        if compact.filter({ $0 == lastSeparator }).count > 1 {
            return groupedDigits(compact, grouping: lastSeparator).flatMap { Double($0) }
        }
        if String(lastSeparator) == groupingSeparator, let digits = groupedDigits(compact, grouping: lastSeparator) {
            return Double(digits)
        }
        return number(compact, decimal: lastSeparator)
    }

    /// Reads `text` with `decimal` as the decimal separator and the other
    /// separator, if any, as grouping.
    private static func number(_ text: String, decimal: Character) -> Double? {
        let parts = text.split(separator: decimal, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts[1].allSatisfy(\.isASCIIDigit) else { return nil }
        let grouping: Character = decimal == "," ? "." : ","
        let integer = parts[0].contains(grouping) ? groupedDigits(parts[0], grouping: grouping) : parts[0]
        guard let integer else { return nil }
        return Double("\(integer.isEmpty ? "0" : integer).\(parts[1].isEmpty ? "0" : parts[1])")
    }

    /// The digits of a whole number grouped by `grouping`, or nil when the
    /// groups are malformed. The last group must have three digits and earlier
    /// ones two or three, which also accepts Indian grouping ("1,23,456"). A
    /// grouped number never starts with a zero, so "0.134" is a decimal even
    /// where "." groups — a SAP value read as 134 would multiply the lye.
    private static func groupedDigits(_ text: String, grouping: Character) -> String? {
        let groups = text.split(separator: grouping, omittingEmptySubsequences: false).map(String.init)
        guard groups.count > 1,
              let first = groups.first, (1...3).contains(first.count), first.first != "0",
              let last = groups.last, last.count == 3,
              groups.dropFirst().dropLast().allSatisfy({ (2...3).contains($0.count) }),
              groups.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        return groups.joined()
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
