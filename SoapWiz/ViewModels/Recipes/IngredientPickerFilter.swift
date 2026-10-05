import Foundation
import SwiftData

/// What `IngredientPickerView` narrows its rows by: the search text, the chosen
/// category chip, and the In stock chip, which is a toggle on top of the
/// category rather than one of the mutually exclusive category chips.
struct IngredientPickerFilter {
    var searchText = ""
    var category: IngredientCategory?
    var inStockOnly = false

    /// The rows the picker lists, favourites first and each group in the order
    /// `ingredients` arrived in. In stock counts low-stock rows: a little left is
    /// still something to make a batch from.
    func choices(
        from ingredients: [Ingredient],
        allowedRoles: Set<RecipeIngredientRole>?,
        includesUnroled: Bool
    ) -> [Ingredient] {
        ingredients.filter { ingredient in
            // Hiding an ingredient is the user saying they don't use it, so it
            // leaves the choices here too, not just Inventory. Unhiding from
            // Filters is the way back.
            guard !ingredient.isHidden else { return false }

            let matchesAllowed = IngredientPickerView.accepts(
                role: ingredient.category?.ingredientRole,
                allowedRoles: allowedRoles,
                includesUnroled: includesUnroled
            )
            let matchesSearch = searchText.isEmpty ||
                ingredient.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = category == nil ||
                ingredient.category?.persistentModelID == category?.persistentModelID
            let matchesStock = !inStockOnly || ingredient.totalRemaining > 0
            return matchesAllowed && matchesSearch && matchesCategory && matchesStock
        }
        .favoritesFirst
    }
}
