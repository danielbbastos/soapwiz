import Foundation
import SwiftData

/// One line on the shopping list: something to buy, whether or not it matches an
/// ingredient the user tracks.
@Model
final class ShoppingListItem {
    var uuid: UUID = UUID()

    /// Shown on the list. Copied from the ingredient when there is one, so the
    /// line stays readable after the ingredient is deleted.
    var name: String = ""

    /// How much to buy, or `nil` when the user only wants a reminder.
    var amount: Double?
    var unit: String = ""

    // Inverse and `.nullify` delete rule are declared on `Ingredient.shoppingListItems`,
    // so a deleted ingredient drops this link and the line survives as a plain name.
    var ingredient: Ingredient?

    /// The library slug of `ingredient` — see `RecipeIngredient.ingredientSlug`.
    var ingredientSlug: String = ""

    var note: String = ""
    var isChecked: Bool = false
    var checkedAt: Date?
    var createdAt: Date = Date.now

    init(
        name: String,
        amount: Double? = nil,
        unit: String = "",
        ingredient: Ingredient? = nil,
        note: String = ""
    ) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.ingredient = ingredient
        self.ingredientSlug = ingredient?.librarySlug ?? ""
        self.note = note
    }
}
