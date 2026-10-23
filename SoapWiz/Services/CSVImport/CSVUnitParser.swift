import Foundation

/// An amount read from a cell like "500 g", with the unit when the cell has one.
nonisolated struct CSVQuantity: Equatable {
    let amount: Double
    let unit: IngredientUnit?
}

/// Reads units of measure as spreadsheets spell them: "Kgs", "lbs.", "litre".
///
/// "fl oz" is deliberately unknown. It is a volume, and mapping it to ounces
/// would silently turn it into a weight.
enum CSVUnitParser {
    private static let synonyms: [IngredientUnit: [String]] = [
        .grams: ["g", "gr", "grs", "gram", "grams", "gramme", "grammes"],
        .kilograms: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"],
        .ounces: ["oz", "ounce", "ounces"],
        .pounds: ["lb", "lbs", "pound", "pounds"],
        .milliliters: ["ml", "millilitre", "millilitres", "milliliter", "milliliters"],
        .liters: ["l", "lt", "ltr", "litre", "litres", "liter", "liters"],
        .units: ["un", "unit", "units", "pc", "pcs", "piece", "pieces", "ea", "each"]
    ]

    private static let unitsByName: [String: IngredientUnit] = Dictionary(
        uniqueKeysWithValues: synonyms.flatMap { unit, names in names.map { ($0, unit) } }
    )

    /// The unit `text` names, ignoring case, accents and a trailing ".".
    static func unit(_ text: String) -> IngredientUnit? {
        var key = text.lookupKey
        if key.hasSuffix(".") {
            key.removeLast()
        }
        return unitsByName[key.trimmingCharacters(in: .whitespaces)]
    }

    /// The amount and unit in each of `cells`, in the same order: "500 g",
    /// "1,5kg", "12". The unit is nil when the cell is only a number. A cell is
    /// nil when its number is unreadable or negative, or when its unit text is
    /// present but unknown. The numbers are read as one column, so they share
    /// `CSVNumberParser`'s decimal mark vote.
    static func quantities(in cells: [String], locale: Locale = .autoupdatingCurrent) -> [CSVQuantity?] {
        let parts = cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            let numberText = trimmed.prefix { $0.isASCII && $0.isNumber || $0 == "." || $0 == "," }
            return (number: String(numberText), unit: trimmed.dropFirst(numberText.count).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let amounts = CSVNumberParser.numbers(in: parts.map(\.number), locale: locale)
        return zip(parts, amounts).map { part, amount in
            guard let amount else { return nil }
            if part.unit.isEmpty {
                return CSVQuantity(amount: amount, unit: nil)
            }
            return unit(part.unit).map { CSVQuantity(amount: amount, unit: $0) }
        }
    }
}
