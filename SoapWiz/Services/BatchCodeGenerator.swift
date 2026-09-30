import Foundation

/// Builds the code a batch is labelled with: `LAV-260930-01` — a short prefix
/// from the recipe name, the day it was made, and a sequence within that pair.
///
/// Shared by batch creation, the launch backfill and the sync deduplicator, so
/// the three can never disagree about what a code looks like or which one comes
/// next. Codes are compared trimmed and case-insensitively throughout, since a
/// hand-typed `lav-260930-01` is the same label as the generated one.
enum BatchCodeGenerator {
    /// Stands in for a recipe name with nothing to abbreviate — empty, or all
    /// punctuation and emoji.
    static let fallbackPrefix = "B"

    /// A label has little room, so the prefix stops here however many words the
    /// recipe name has.
    private static let prefixLength = 3

    /// Sequences below this many digits are zero-padded, so a day's first batch
    /// reads `-01`. A hundredth batch simply takes the third digit.
    private static let sequenceWidth = 2

    private static let dateStampLength = 6

    /// A tail longer than this isn't a sequence anyone counted up to — it is
    /// something typed by hand — and counting on from it could overflow.
    private static let maxSequenceDigits = 9

    /// The code as it is stored and shown: what was typed, without the stray
    /// space a keyboard leaves at either end.
    static func trimmed(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The form codes are compared in.
    static func normalized(_ code: String) -> String {
        trimmed(code).uppercased()
    }

    /// Up to three characters abbreviating `recipeName`, by the same rules that
    /// abbreviate an ingredient name. Punctuation is dropped first so the prefix
    /// never carries a hyphen of its own.
    static func prefix(for recipeName: String) -> String {
        let cleaned = String(recipeName.compactMap { character -> Character? in
            if character.isWhitespace { return " " }
            return character.isLetter || character.isNumber ? character : nil
        })
        let suggested = IngredientCodeSuggester.suggest(for: cleaned, existingCodes: [])
        return suggested.isEmpty ? fallbackPrefix : String(suggested.prefix(prefixLength))
    }

    /// `yyMMdd` for the day `date` falls on in `timeZone`. Always Gregorian and
    /// always ASCII digits, whatever calendar and numerals the device uses — the
    /// code is an identifier, not a formatted date.
    static func dateStamp(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [(parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0]
            .map { padded($0, to: 2) }
            .joined()
    }

    /// Everything before the sequence: `LAV-260930`.
    static func stem(recipeName: String, date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix(for: recipeName))-\(dateStamp(for: date, timeZone: timeZone))"
    }

    /// The code a batch of `recipeName` made on `date` should take, given the
    /// codes already in use.
    static func suggestedCode(
        recipeName: String,
        date: Date,
        existingCodes: some Sequence<String>,
        timeZone: TimeZone = .current
    ) -> String {
        nextCode(in: stem(recipeName: recipeName, date: date, timeZone: timeZone), existingCodes: existingCodes)
    }

    /// `<stem>-<n>`, where `n` is one past the highest sequence already recorded
    /// under `stem`. Gaps are not refilled: a number that was once on a label is
    /// never handed to a different batch.
    static func nextCode(in stem: String, existingCodes: some Sequence<String>) -> String {
        let highest = existingCodes.compactMap { sequence(of: $0, in: stem) }.max() ?? 0
        return "\(stem)-\(padded(highest + 1, to: sequenceWidth))"
    }

    /// The sequence number `code` holds under `stem`, or `nil` when it belongs
    /// to another stem or its tail isn't a number a sequence could have reached.
    static func sequence(of code: String, in stem: String) -> Int? {
        let prefix = "\(normalized(stem))-"
        let code = normalized(code)
        guard code.hasPrefix(prefix) else { return nil }
        let digits = code.dropFirst(prefix.count)
        guard isNumber(digits), digits.count <= maxSequenceDigits else { return nil }
        return Int(digits)
    }

    /// The stem of a code that has the generated shape — `<prefix>-<yyMMdd>-<n>`
    /// — or `nil` for anything else. Read off the code itself rather than
    /// recomputed from the batch, so every device takes the same stem from the
    /// same code whatever time zone it is in.
    static func generatedStem(of code: String) -> String? {
        let parts = normalized(code).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let sequence = parts.last, sequence.count >= sequenceWidth, isNumber(sequence) else { return nil }
        let stamp = parts[parts.count - 2]
        guard stamp.count == dateStampLength, isNumber(stamp) else { return nil }
        let stem = parts.dropLast().joined(separator: "-")
        guard stem.count > dateStampLength + 1 else { return nil }
        return stem
    }

    /// Whether a batch other than `batch` already carries `code`. An empty code
    /// is never a duplicate — it is simply missing.
    static func isTaken(_ code: String, among batches: [Batch], excluding batch: Batch? = nil) -> Bool {
        let code = normalized(code)
        guard !code.isEmpty else { return false }
        return batches.contains { $0 !== batch && normalized($0.code) == code }
    }

    private static func isNumber(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func padded(_ number: Int, to width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
