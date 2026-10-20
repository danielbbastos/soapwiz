import Foundation

/// Oil tables whose columns are named by a header line.
///
/// Soapmaking Friend and SoapCalc print every oil with a share and a weight in
/// each unit, under a header such as "Oil % Ounces Grams". The model has read
/// such a table by position instead: it took the Ounces column for grams,
/// the post-cook superfat row's total for the batch, and the batch weight
/// including water for the oil weight. The header says which number is which,
/// so a table it describes is read from it and the model's reading is replaced.
extension RecipeImportDraftChecker {
    /// The draft as a percentage recipe read from a table's columns; `nil` when
    /// the text has no such table for every one of the draft's oils.
    ///
    /// Each oil takes the share in its own row, found among the lines under the
    /// header up to the "Total" line. The row's numbers are matched to the
    /// header's columns from the right, so a leading row number ("1") or digits
    /// in the name ("Coconut Oil, 76 deg") never shift a column. When the name
    /// stands alone on its line, the numbers are on the line below. Rows that
    /// match none of the draft's oils, such as "Super Fat after cook", are
    /// ignored. The batch size is one weight column summed over the oils, in the
    /// draft's own unit when the table has it. Shares that don't make a whole
    /// blend leave the draft alone, as with `statedPercentageRecipe`.
    static func oilTableRecipe(_ draft: RecipeImportDraft, in text: String) -> RecipeImportDraft? {
        guard !draft.oils.isEmpty else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard let headerIndex = lines.firstIndex(where: { OilTableColumns(header: $0) != nil }),
              let columns = OilTableColumns(header: lines[headerIndex]) else { return nil }

        let rows = oilTableRows(in: lines[(headerIndex + 1)...])
        var found: [[Double]] = []
        for oil in draft.oils {
            let key = oil.name.lookupKey
            guard !key.isEmpty,
                  let numbers = rows.first(where: { $0.name.lookupKey.contains(key) })?.numbers,
                  numbers.count >= columns.kinds.count else { return nil }
            found.append(Array(numbers.suffix(columns.kinds.count)))
        }

        guard let shareColumn = columns.kinds.firstIndex(of: .share) else { return nil }
        let shares = found.map { $0[shareColumn] }
        guard wholeBlend.contains(shares.reduce(0, +)) else { return nil }

        guard let weightColumn = columns.weightColumn(preferring: draft.batchUnit),
              case .weight(let unit) = columns.kinds[weightColumn] else { return nil }
        let batchSize = found.map { $0[weightColumn] }.reduce(0, +)

        var recipe = draft
        for (index, share) in zip(recipe.oils.indices, shares) {
            recipe.oils[index].amount = share
            recipe.oils[index].unit = "%"
        }
        recipe.amountsArePercentages = true
        recipe.batchSize = (batchSize * 1000).rounded() / 1000
        recipe.batchUnit = unit
        return recipe
    }

    /// The table's rows: a name and the numbers that end its line, or end the
    /// line below when the name's own line has none. Reading stops at "Total".
    private static func oilTableRows(in lines: ArraySlice<String>) -> [(name: String, numbers: [Double])] {
        var rows: [(name: String, numbers: [Double])] = []
        let candidates = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var index = candidates.startIndex
        while index < candidates.endIndex {
            let line = candidates[index]
            index += 1
            let firstWord = line.split(whereSeparator: \.isWhitespace).first?.lowercased()
            if firstWord == "total" || firstWord == "totals" { break }

            let split = splitTrailingNumbers(line)
            if !split.numbers.isEmpty {
                rows.append(split)
            } else if index < candidates.endIndex {
                let below = splitTrailingNumbers(candidates[index])
                if below.name.isEmpty, !below.numbers.isEmpty {
                    rows.append((name: split.name, numbers: below.numbers))
                    index += 1
                }
            }
        }
        return rows
    }

    private static let tableNumber = #/\d+(?:[.,]\d+)?/#

    /// A line cut into its name and the run of numeric cells at its end. Cells
    /// are tab-separated when the line has tabs, else words.
    private static func splitTrailingNumbers(_ line: String) -> (name: String, numbers: [Double]) {
        let separator: (Character) -> Bool = line.contains("\t") ? { $0 == "\t" } : { $0.isWhitespace }
        var cells = line.split(omittingEmptySubsequences: true, whereSeparator: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var numbers: [Double] = []
        while let last = cells.last, last.wholeMatch(of: tableNumber) != nil,
              let value = RecipeTextNumbers.decimal(Substring(last)) {
            numbers.insert(value, at: 0)
            cells.removeLast()
        }
        return (cells.joined(separator: " "), numbers)
    }
}

/// The numeric columns a table header names, in order. Cells that are not a
/// share or a weight ("#", "Oil/Fat") are not columns and are left out.
private struct OilTableColumns {
    enum Kind: Equatable {
        case share
        case weight(unit: String)
    }

    private static let units: [String: String] = [
        "pounds": "lb", "pound": "lb", "lb": "lb", "lbs": "lb",
        "ounces": "oz", "ounce": "oz", "oz": "oz",
        "grams": "g", "gram": "g", "g": "g", "gr": "g",
        "kilos": "kg", "kilo": "kg", "kilograms": "kg", "kg": "kg"
    ]

    let kinds: [Kind]

    /// `nil` unless the line names a share column and at least one weight. A
    /// line with a number in it is a value, not a header: "NaOH Weight at 99 %
    /// Purity 14.67 oz 415.97 g" has a % and weights but names no columns.
    init?(header: String) {
        guard !header.contains(where: \.isNumber) else { return nil }
        let kinds = header.split(whereSeparator: \.isWhitespace).compactMap { cell -> Kind? in
            if cell == "%" { return .share }
            return Self.units[cell.lowercased()].map { .weight(unit: $0) }
        }
        guard kinds.contains(.share), kinds.count > 1,
              kinds.contains(where: { if case .weight = $0 { true } else { false } }) else { return nil }
        self.kinds = kinds
    }

    /// The weight column to total: the draft's unit when the table has it,
    /// else grams, ounces, or whichever weight comes first.
    func weightColumn(preferring batchUnit: String?) -> Int? {
        let unitOf: (Int) -> String? = {
            if case .weight(let unit) = kinds[$0] { unit } else { nil }
        }
        let weights = kinds.indices.filter { unitOf($0) != nil }
        let preferred = [batchUnit?.lowercased(), "g", "oz"].compactMap { $0 }
        for unit in preferred {
            if let column = weights.first(where: { unitOf($0) == unit }) { return column }
        }
        return weights.first
    }
}
