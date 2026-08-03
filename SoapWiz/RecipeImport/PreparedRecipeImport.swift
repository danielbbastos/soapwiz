import Foundation

/// A reviewed import, ready to open the recipe form with.
///
/// Carries the extracted configuration and the rows the user resolved. The `id`
/// makes each request distinct so navigating to the same import twice is still
/// two separate pushes — the same reason `RecipeSeed` has one.
struct PreparedRecipeImport: Hashable {
    let id = UUID()
    let draft: RecipeImportDraft
    let rows: [RecipeImportRow]

    static func == (lhs: PreparedRecipeImport, rhs: PreparedRecipeImport) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func rows(for role: RecipeIngredientRole) -> [RecipeImportRow] {
        rows.filter { $0.role == role }
    }

    /// Ingredients the user chose not to create, described the way they were
    /// written in the source so the information survives in the recipe's notes.
    var skippedDescriptions: [String] {
        rows.filter { $0.resolution == .skipped }.map { row in
            let amount = row.imported.amount
            guard amount > 0 else { return row.imported.name }
            let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
            let unit = row.imported.unit ?? (draft.amountsArePercentages ? "%" : draft.resolvedBatchUnit)
            return "\(row.imported.name) \(formatted)\(unit == "%" ? "" : " ")\(unit)"
        }
    }
}
