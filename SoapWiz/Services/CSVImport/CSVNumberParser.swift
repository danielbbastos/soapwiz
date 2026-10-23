import Foundation

/// Reads a column of numbers from a CSV file, whichever decimal mark the file
/// was exported with.
///
/// A file's numbers follow the exporter's locale, not the phone's, so a German
/// export read in a US locale would turn "1,5" into 15. The column is read as
/// a whole instead: each value that can only be one reading votes for it —
/// "1,5", "12,50" and "1.234,5" for the comma, "1.5" and "1,234.5" for the
/// point — while "1,000", "1.000" and "15" are ambiguous and don't vote. A
/// column with only comma votes is read as comma-decimal, one with only point
/// votes as point-decimal, and anything else with the locale passed in. The
/// reading itself is `LocaleDecimal`'s, except that a value with a space in it
/// ("1 234,5") is grouped by spaces whatever the column's locale.
///
/// Currency symbols and ISO currency codes on either side of a number are
/// ignored. Empty, unreadable and negative values are nil.
enum CSVNumberParser {
    private static let commaDecimalLocale = Locale(identifier: "de_DE")
    private static let pointDecimalLocale = Locale(identifier: "en_US")
    private static let spaceGroupingLocale = Locale(identifier: "fr_FR")
    private static let currencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    /// The number in each of `cells`, in the same order.
    static func numbers(in cells: [String], locale: Locale = .autoupdatingCurrent) -> [Double?] {
        let cleaned = cells.map { withoutCurrency($0) }
        let columnLocale = columnLocale(for: cleaned, fallback: locale)
        return cleaned.map { text in
            guard !text.isEmpty,
                  let value = LocaleDecimal.parse(text, locale: text.contains(where: \.isWhitespace) ? spaceGroupingLocale : columnLocale),
                  value >= 0, value.isFinite else { return nil }
            return value
        }
    }

    private static func columnLocale(for cleaned: [String], fallback: Locale) -> Locale {
        let marks = cleaned.compactMap { decimalMark(of: $0) }
        let hasComma = marks.contains(",")
        let hasPoint = marks.contains(".")
        if hasComma, !hasPoint { return commaDecimalLocale }
        if hasPoint, !hasComma { return pointDecimalLocale }
        return fallback
    }

    /// The decimal mark `text` can only be using, or nil when it could be
    /// either. With both marks the last one is the decimal. A mark that repeats
    /// is grouping. A single mark is grouping only when exactly three digits
    /// follow a short first group that doesn't start with zero ("1,000" but
    /// not "0,500" or "1234,500").
    private static func decimalMark(of text: String) -> Character? {
        let compact = text.filter { !$0.isWhitespace }.drop { $0 == "-" }
        guard !compact.isEmpty,
              compact.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              let last = compact.last(where: { $0 == "." || $0 == "," }) else { return nil }
        if compact.contains(".") && compact.contains(",") { return last }
        let parts = compact.split(separator: last, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let isGrouping = parts[1].count == 3 && (1...3).contains(parts[0].count) && parts[0].first != "0"
        return isGrouping ? nil : last
    }

    private static func withoutCurrency(_ cell: String) -> String {
        var text = cell.replacingOccurrences(of: "R$", with: "")
        text.unicodeScalars.removeAll { $0.properties.generalCategory == .currencySymbol }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let leading = text.prefix { $0.isLetter }
        if leading.count == 3, currencyCodes.contains(leading.uppercased()) {
            text.removeFirst(3)
        }
        let trailing = String(text.reversed().prefix { $0.isLetter }.reversed())
        if trailing.count == 3, currencyCodes.contains(trailing.uppercased()) {
            text.removeLast(3)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
