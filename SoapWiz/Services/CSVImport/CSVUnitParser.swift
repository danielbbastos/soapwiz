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
nonisolated enum CSVUnitParser {
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
    /// "1,5kg", "12". A cell is split at its first letter: the number is
    /// everything before it, spaces included, so "1 234 g" is 1234 grams, and
    /// the unit is the rest. The unit is nil when the cell has no letters. A
    /// cell is nil when its number is unreadable or negative, or when its unit
    /// text is present but unknown. The numbers are read as one column, so they
    /// share `CSVNumberParser`'s decimal mark vote.
    static func quantities(in cells: [String], locale: Locale = .autoupdatingCurrent) -> [CSVQuantity?] {
        let parts = cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            let split = trimmed.firstIndex { $0.isLetter } ?? trimmed.endIndex
            return (
                number: trimmed[..<split].trimmingCharacters(in: .whitespacesAndNewlines),
                unit: trimmed[split...].trimmingCharacters(in: .whitespacesAndNewlines)
            )
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
