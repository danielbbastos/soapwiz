import Foundation

/// The numbers a piece of recipe text actually contains, read every way a
/// person might have written them.
///
/// Used to check the model's output against its input: an amount or a setting
/// whose number appears nowhere in the text was invented, however plausible it
/// looks on the review screen.
enum RecipeTextNumbers {
    private static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "⅛": 0.125
    ]

    /// Every value `text` could be read as containing.
    ///
    /// Ambiguous separators yield each reading rather than a guess: "1,000" is
    /// both a thousand and, in a comma-decimal locale, one. A false match only
    /// keeps a number the text really does contain, so over-reading is safe.
    static func values(in text: String) -> [Double] {
        var values: [Double] = []
        var fractionRanges: [Range<String.Index>] = []

        for match in text.matches(of: #/(?:(\d+)\h+)?(\d+)\h*\/\h*(\d+)/#) {
            guard let numerator = Double(match.output.2), let denominator = Double(match.output.3),
                  denominator > 0 else { continue }
            fractionRanges.append(match.range)
            values.append(mixed(whole: match.output.1, fraction: numerator / denominator))
        }
        for match in text.matches(of: #/(?:(\d+)\h*)?([½¼¾⅓⅔⅛])/#) {
            guard let character = match.output.2.first, let fraction = vulgarFractions[character] else { continue }
            fractionRanges.append(match.range)
            values.append(mixed(whole: match.output.1, fraction: fraction))
        }
        // The parts of a fraction are not numbers the text states: "1/2 cup"
        // says nothing about 2 of anything, and reading it would let an
        // invented amount of 2 pass.
        for match in text.matches(of: #/\d+(?:[.,]\d+)*/#)
        where !fractionRanges.contains(where: { $0.overlaps(match.range) }) {
            values.append(contentsOf: readings(of: String(match.output)))
        }
        return values
    }

    static func contains(_ value: Double, in values: [Double]) -> Bool {
        let tolerance = 1e-6 * max(1, abs(value))
        return values.contains { abs($0 - value) <= tolerance }
    }

    /// A single written number with a dot or comma decimal separator.
    static func decimal(_ token: Substring) -> Double? {
        Double(token.replacingOccurrences(of: ",", with: "."))
    }

    private static func readings(of token: String) -> [Double] {
        let separatorCount = token.filter { $0 == "." || $0 == "," }.count
        var readings = [
            Double(token.replacingOccurrences(of: ",", with: "")),
            Double(token.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        ]
        if separatorCount == 1 {
            readings.append(Double(token.replacingOccurrences(of: ",", with: ".")))
        }
        return readings.compactMap { $0 }
    }

    private static func mixed(whole: Substring?, fraction: Double) -> Double {
        whole.flatMap { Double($0) }.map { $0 + fraction } ?? fraction
    }
}
