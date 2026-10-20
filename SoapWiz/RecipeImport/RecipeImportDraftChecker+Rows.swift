import Foundation

/// Which section each row sits in, and which rows are one row read twice.
///
/// The model files rows by position in the text rather than by what they are:
/// it has listed essential oils, clay and honey under Oils because they sat
/// beneath a lye-and-oils block, and repeated one fragrance a dozen times. An
/// oil row feeds the lye calculation, so a stray additive there is a wrong lye
/// weight rather than a cosmetic slip.
extension RecipeImportDraftChecker {
    /// Units a spoon, cup, drop or liquid measure is written in. A row measured
    /// this way is taken for an additive only when its name doesn't say it is
    /// an oil, butter or wax.
    private static let measuredByVolume: Set<String> = [
        "tsp", "tbsp", "teaspoon", "teaspoons", "tablespoon", "tablespoons",
        "cup", "cups", "ml", "l", "drop", "drops"
    ]

    /// The draft with rows moved to the section their name or unit shows.
    ///
    /// A name's wording decides first (`ImportedIngredientName.evidentRole`):
    /// fragrance wording wins, then additive wording. An oil, butter or wax has
    /// no evident role and stays where the model put it. Beyond that, an oil
    /// row in a spoon or volume unit moves to the additives, unless its name
    /// says fragrance or says it is an oil: "1 L de aceite de oliva" is a real
    /// oil whose amount the checker later clears, not a liquid additive. Rows
    /// the model put under Fragrances are left alone, and an additive moves
    /// only when it reads as a fragrance.
    static func movingMisplacedRows(_ draft: RecipeImportDraft) -> RecipeImportDraft {
        var moved = draft
        moved.oils = []
        for row in draft.oils {
            switch section(of: row, listedAs: .oil) {
            case .oil: moved.oils.append(row)
            case .additive: moved.additives.append(row)
            case .fragrance: moved.fragrances.append(row)
            }
        }
        var additives: [ImportedIngredient] = []
        for row in moved.additives {
            switch section(of: row, listedAs: .additive) {
            case .fragrance: moved.fragrances.append(row)
            case .oil, .additive: additives.append(row)
            }
        }
        moved.additives = additives
        return moved
    }

    private static func section(of row: ImportedIngredient, listedAs role: RecipeIngredientRole) -> RecipeIngredientRole {
        let evident = ImportedIngredientName.evidentRole(of: row.name)
        if evident == .fragrance { return .fragrance }
        guard role == .oil else { return role }
        if evident == .additive { return .additive }
        if isMeasuredByVolume(row), !ImportedIngredientName.hasOilWording(row.name) { return .additive }
        return role
    }

    private static func isMeasuredByVolume(_ row: ImportedIngredient) -> Bool {
        guard var normalized = row.normalizedUnit else { return false }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return measuredByVolume.contains(normalized)
    }

    /// The draft with each row listed once.
    ///
    /// Two rows are the same when they share a name, an amount and a unit, the
    /// unit compared without regard to case. The first is kept. A row that is
    /// also a fragrance is removed from the oils and additives, since the
    /// fragrance section is where a repeat of it belongs; one that appears
    /// in the oils and the additives is left in both.
    static func removingDuplicates(_ draft: RecipeImportDraft) -> RecipeImportDraft {
        var unique = draft
        unique.oils = uniqueRows(draft.oils)
        unique.additives = uniqueRows(draft.additives)
        unique.fragrances = uniqueRows(draft.fragrances)

        let fragranceKeys = Set(unique.fragrances.map(RowKey.init))
        unique.oils.removeAll { fragranceKeys.contains(RowKey($0)) }
        unique.additives.removeAll { fragranceKeys.contains(RowKey($0)) }
        return unique
    }

    private static func uniqueRows(_ rows: [ImportedIngredient]) -> [ImportedIngredient] {
        var seen: Set<RowKey> = []
        return rows.filter { seen.insert(RowKey($0)).inserted }
    }
}

private struct RowKey: Hashable {
    let name: String
    let amount: Double
    let unit: String?

    init(_ row: ImportedIngredient) {
        name = row.name.lookupKey
        amount = row.amount
        unit = row.normalizedUnit
    }
}
