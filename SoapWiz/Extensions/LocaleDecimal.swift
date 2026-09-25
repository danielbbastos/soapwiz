import Foundation

/// Reads a number the user typed, in their own locale.
///
/// A plain `Double(text)` only understands a point, and swapping every comma
/// for a point turns an English "1,500" into 1.5. This reads the locale's
/// separators instead, and stays lenient about the other one where the text is
/// unambiguous. The rules, in the order they apply:
///
/// 1. A locale's own mark other than "." and "," (the Arabic "٬", the Swiss
///    "’", the French space) is grouping, and the whole part must be properly
///    grouped: "1’234.5" is 1234.5, "1’5" is unreadable.
/// 2. With both "." and ",", the last one is the decimal in any locale:
///    "1.234,5" is 1234.5 even in the US.
/// 3. A separator that repeats is grouping in any locale: "1,500,000" is
///    1500000 even in Germany.
/// 4. A single separator is grouping only when it is the locale's grouping
///    separator and the digits after it form whole groups: "1.500" is 1500 in
///    Germany, but "1.5" and "0.134" are decimals there.
/// 5. Otherwise it is the decimal: "1,5" is 1.5 even in the US.
///
/// Whole groups have three digits (the first one to three, never starting
/// with 0), so a grouped reading never shrinks or inflates a decimal.
///
/// Pasted recipe text goes through `RecipeTextNumbers` instead — that is
/// foreign text, not the user's own input.
enum LocaleDecimal {
    /// Whether a numeric field's text can be saved: empty, or a number. A form
    /// must refuse to save anything else rather than store it as nothing.
    static func isReadable(_ text: String, locale: Locale = .autoupdatingCurrent) -> Bool {
        text.allSatisfy(\.isWhitespace) || parse(text, locale: locale) != nil
    }

    /// Whether `character` can be part of a number typed in `locale`. The
    /// input filter keeps exactly these, so it never drops a separator the
    /// parser would need — dropping the full-width point from "１．５" left
    /// "１５", which reads as 15. The minus sign is left out on purpose: no
    /// field takes a negative number.
    static func isNumberCharacter(_ character: Character, locale: Locale = .autoupdatingCurrent) -> Bool {
        if isDecimalDigit(character) || ".,\u{FF0E}\u{FF0C}".contains(character) { return true }
        let separators = [locale.groupingSeparator, locale.decimalSeparator].compactMap(\.self)
        return separators.contains(String(character)) || (character.isWhitespace && groupsWithSpace(locale))
    }

    /// The number in `text`, or nil when it isn't one. A leading minus is read
    /// rather than rejected, so a caller that gets text past the input filter
    /// clamps or refuses a negative value itself.
    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        var compact = String(normalized(text.trimmingCharacters(in: .whitespaces), locale: locale))
        let isNegative = compact.first == "-"
        if isNegative {
            compact.removeFirst()
        }
        return magnitude(compact, groupingSeparator: locale.groupingSeparator ?? ",")
            .map { isNegative ? -$0 : $0 }
    }

    /// Rewrites `text` into ASCII digits, ".", "," and `groupingMark`. A
    /// locale's own marks other than "." and "," — the Arabic "٫" and "٬", the
    /// Swiss "’", the French space — become the point and `groupingMark`, so
    /// they go through the same checks rather than being dropped unchecked: a
    /// dropped "٬" read "٠٬١٣٤" as 134.
    private static func normalized(_ text: String, locale: Locale) -> [Character] {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        return text.map { character in
            let string = String(character)
            if string == decimalSeparator, decimalSeparator != ".", decimalSeparator != "," { return "." }
            if string == groupingSeparator, groupingSeparator != ".", groupingSeparator != "," { return groupingMark }
            if character.isWhitespace { return groupsWithSpace(locale) ? groupingMark : character }
            switch character {
            case "\u{FF0E}": return "."
            case "\u{FF0C}": return ","
            case "\u{2212}": return "-"
            default: return asciiDigit(character)
            }
        }
    }

    private static func magnitude(_ compact: String, groupingSeparator: String) -> Double? {
        if compact.contains(groupingMark) {
            return markGrouped(compact)
        }
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
        guard let integer, !(integer.isEmpty && parts[1].isEmpty) else { return nil }
        return Double("\(integer.isEmpty ? "0" : integer).\(parts[1].isEmpty ? "0" : parts[1])")
    }

    /// A number grouped by the locale's own mark, which is never "." or ",", so
    /// whichever of those comes last is the decimal and the whole part must be
    /// properly grouped.
    private static func markGrouped(_ text: String) -> Double? {
        let decimalIndex = text.lastIndex { $0 == "." || $0 == "," }
        let integerText = decimalIndex.map { String(text[..<$0]) } ?? text
        let fraction = decimalIndex.map { String(text[text.index(after: $0)...]) } ?? ""
        guard fraction.allSatisfy(\.isASCIIDigit),
              let digits = groupedDigits(integerText, grouping: groupingMark) else { return nil }
        return Double(fraction.isEmpty ? digits : "\(digits).\(fraction)")
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

private extension LocaleDecimal {
    /// Stands in for a locale's own grouping mark; a private-use character, so
    /// nothing typed can collide with it.
    static let groupingMark: Character = "\u{E000}"

    /// Only true decimal digits in any script; "²" or "①" are numbers too but
    /// not digits, and reading "1²" as 12 would be a silent typo.
    static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first?.properties.numericType == .decimal
    }

    static func asciiDigit(_ character: Character) -> Character {
        guard !character.isASCII, isDecimalDigit(character), let value = character.wholeNumberValue else { return character }
        return Character(String(value))
    }

    /// French and Portuguese group with a (no-break) space, so a space inside
    /// a number is grouping there.
    static func groupsWithSpace(_ locale: Locale) -> Bool {
        locale.groupingSeparator?.allSatisfy(\.isWhitespace) ?? false
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
