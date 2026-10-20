import Foundation

extension RecipeTextSettingsParser {
    // MARK: - Labels and values on separate lines

    private static let settingLabel =
        #/
        (?:
            super\h*-?\h*fat(?:ting)?
            |lye\h+discount
            |sf
            |sobre\h*-?\h*engr?as(?:ado|e)
            |lye\h+concentration
            |concentraci[oó]n
            |water\h*(?::|\/|to)\h*lye(?:\h+ratio)?
            |water\h+ratio
            |fragrance(?:\h+load)?
            |scent(?:\h+load)?
        )\b
        /#.ignoresCase()
    private static let settingValue = #/\d+(?:[.,]\d+)?\h*%?/#

    /// The text with a row of setting labels joined to the row of values under
    /// it, so each pair reads as it would written on one line.
    ///
    /// A screenshot of a settings panel is recognised label by label and then
    /// value by value: "Sobreengrasado Concentración" on one line and "8% 30%"
    /// on the next. When a line holds nothing but labels and the next
    /// non-empty line holds nothing but as many values, they are paired left to
    /// right. Any other shape is left alone, since a count that doesn't match
    /// or an ingredient line in between means the numbers belong to something
    /// else.
    static func joiningLabelRows(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var index = 0
        while index < lines.count {
            if let labels = settingLabels(in: lines[index]),
               let next = lines[(index + 1)...].firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               let values = settingValues(in: lines[next]), values.count == labels.count {
                result.append(contentsOf: zip(labels, values).map { "\($0) \($1)" })
                index = next + 1
            } else {
                result.append(lines[index])
                index += 1
            }
        }
        return result.joined(separator: "\n")
    }

    private static func settingLabels(in line: String) -> [String]? {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        var labels: [String] = []
        while !rest.isEmpty {
            guard let match = rest.prefixMatch(of: settingLabel) else { return nil }
            labels.append(String(rest[match.range]))
            rest = rest[match.range.upperBound...].drop { $0.isWhitespace }
        }
        return labels.isEmpty ? nil : labels
    }

    private static func settingValues(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let values = trimmed.matches(of: settingValue).map { String($0.output).trimmingCharacters(in: .whitespaces) }
        guard !values.isEmpty, trimmed.replacing(settingValue, with: "").allSatisfy(\.isWhitespace) else { return nil }
        return values
    }
}
