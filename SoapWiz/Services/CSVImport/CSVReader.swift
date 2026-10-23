import Foundation

/// Splits CSV text into rows of cells, following RFC 4180 and the ways real
/// spreadsheet exports bend it.
///
/// - A field that starts with a quote is quoted: delimiters and line breaks
///   inside it are kept, and `""` is a literal quote. A quote anywhere else in
///   a field is kept as it is.
/// - Lines end with CRLF, LF or CR, in any mix.
/// - A leading byte order mark is ignored, and trailing rows with no content
///   are dropped. Rows keep the cells they have, so a short or long row is
///   never padded or cut.
///
/// The delimiter is the one of tab, ";" and "," that splits the first 20 rows
/// most consistently, looking at no more than the first 65,536 characters so a
/// file with an unclosed quote isn't scanned three times over. For each, the
/// rows with more than one cell are grouped by cell count: the delimiter whose
/// most common count covers the most rows wins, then the one with the higher
/// count, then the first of tab, ";", ",". Delimiters inside quotes don't
/// count. When the character limit cuts the sample short, its last row may be
/// cut mid-row and is left out, unless it is the only row there is. A file
/// where none of them makes more than one cell is read with ",".
enum CSVReader {
    private static let candidates: [Character] = ["\t", ";", ","]
    private static let sampleRowCount = 20
    private static let sampleCharacterLimit = 65_536

    /// The rows of cells in `text`, split on the delimiter detected from it.
    static func rows(from text: String) -> [[String]] {
        let body = text.unicodeScalars.first == "\u{FEFF}" ? String(text.unicodeScalars.dropFirst()) : text
        let characters = Array(body)
        let delimiter = detectDelimiter(in: characters)
        var rows = split(characters[...], on: delimiter, limit: nil)
        while let last = rows.last, last.allSatisfy({ $0.allSatisfy(\.isWhitespace) }) {
            rows.removeLast()
        }
        return rows
    }

    private static func detectDelimiter(in characters: [Character]) -> Character {
        let sample = characters.prefix(sampleCharacterLimit)
        let isCutShort = characters.count > sampleCharacterLimit
        var best: DelimiterScore?
        for delimiter in candidates {
            var sampled = split(sample, on: delimiter, limit: sampleRowCount)
            if isCutShort, sampled.count > 1, sampled.count < sampleRowCount {
                sampled.removeLast()
            }
            let counts = sampled.map(\.count).filter { $0 > 1 }
            let frequencies = Dictionary(grouping: counts, by: \.self).mapValues(\.count)
            guard let modal = frequencies.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            let score = DelimiterScore(delimiter: delimiter, rowCount: modal.value, cellCount: modal.key)
            if let current = best, !score.beats(current) { continue }
            best = score
        }
        return best?.delimiter ?? ","
    }

    /// The rows of `characters` split on `delimiter`, stopping after `limit` rows.
    private static func split(_ characters: ArraySlice<Character>, on delimiter: Character, limit: Int?) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var isInsideQuotes = false
        var index = characters.startIndex

        while index < characters.endIndex {
            let character = characters[index]
            index += 1
            if isInsideQuotes {
                if character != "\"" {
                    field.append(character)
                } else if index < characters.endIndex, characters[index] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isInsideQuotes = false
                }
            } else if character == "\"", field.isEmpty, !isQuoted {
                isInsideQuotes = true
                isQuoted = true
            } else if character == delimiter {
                row.append(field)
                field = ""
                isQuoted = false
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                isQuoted = false
                if rows.count == limit { return rows }
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty || isQuoted {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

/// How well a delimiter splits the sampled rows: how many rows share its most
/// common cell count, and what that count is.
private struct DelimiterScore {
    let delimiter: Character
    let rowCount: Int
    let cellCount: Int

    func beats(_ other: DelimiterScore) -> Bool {
        (rowCount, cellCount) > (other.rowCount, other.cellCount)
    }
}
