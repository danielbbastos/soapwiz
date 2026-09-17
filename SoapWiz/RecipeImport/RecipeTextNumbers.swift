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

        for match in text.matches(of: #/\d+(?:[.,]\d+)*/#) {
            values.append(contentsOf: readings(of: String(match.output)))
        }
        for match in text.matches(of: #/(\d+)\h*\/\h*(\d+)/#) {
            guard let numerator = Double(match.output.1), let denominator = Double(match.output.2),
                  denominator > 0 else { continue }
            values.append(numerator / denominator)
            if let whole = wholeNumber(before: match.range.lowerBound, in: text) {
                values.append(whole + numerator / denominator)
            }
        }
        for match in text.matches(of: #/(\d+)?\h*([½¼¾⅓⅔⅛])/#) {
            guard let character = match.output.2.first, let fraction = vulgarFractions[character] else { continue }
            values.append(fraction)
            if let whole = match.output.1.flatMap({ Double($0) }) {
                values.append(whole + fraction)
            }
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

    /// The whole number of a mixed fraction such as "1 1/2".
    private static func wholeNumber(before index: String.Index, in text: String) -> Double? {
        let prefix = text[..<index]
        guard let match = prefix.firstMatch(of: #/(\d+)\h+$/#) else { return nil }
        return Double(match.output.1)
    }
}
