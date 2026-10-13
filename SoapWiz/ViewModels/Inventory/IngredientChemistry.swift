import Foundation

/// What an ingredient's chemistry panel needs to know, shared by the ingredient
/// detail page and the oil properties sheet opened from a recipe.
@MainActor
struct IngredientChemistry {
    let ingredient: Ingredient

    /// Whether to show the chemistry block at all. Mirrors the form's gate
    /// (`IngredientFormViewModel.showsSapValue`): only oils carry a SAP value and
    /// a fatty-acid composition, so only oils get the panel.
    var showsChemistry: Bool {
        ingredient.category?.showsSapValue ?? false
    }

    /// True only when a real profile is on file. A nil or all-zero profile is
    /// "not specified" rather than a genuine all-zero oil, so the acid tables and
    /// the qualities chart are replaced by a note instead of a page of `0.00 %`.
    var hasFattyAcidProfile: Bool {
        guard let profile = ingredient.fattyAcidProfile else { return false }
        return !profile.isEmpty
    }

    /// The ingredient's own chemistry expressed as a one-oil blend, so the detail
    /// page reuses `RecipeStats` and the recipe stats views verbatim — the
    /// weighted sum of a single profile is that profile, and the SAP/iodine/INS
    /// fall out with it. `nil` for anything that isn't an oil.
    var stats: RecipeStats? {
        guard showsChemistry else { return nil }
        return RecipeStats(oilDrafts: [OilIngredientDraft(ingredient: ingredient, amount: 1)])
    }
}
