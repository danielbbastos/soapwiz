import Foundation

/// The one order every recipe screen lists its ingredients in. `Recipe.ingredients`
/// is an unordered to-many relationship, so its raw order differs between
/// devices and launches; sorting by amount alone leaves equal amounts to the
/// same luck.
enum RecipeIngredientOrder {
    /// Largest amount first, then name. The name goes through `lookupKey` so
    /// the tie-break is the same on every device and locale.
    static func precedes(amount: Double, name: String, before otherAmount: Double, otherName: String) -> Bool {
        if amount != otherAmount { return amount > otherAmount }
        return name.lookupKey < otherName.lookupKey
    }
}

protocol RecipeOrderedDraft {
    var amount: Double { get }
    var ingredient: Ingredient { get }
}

extension OilIngredientDraft: RecipeOrderedDraft {}
extension IngredientAmountDraft: RecipeOrderedDraft {}

extension Sequence where Element: RecipeOrderedDraft {
    var inRecipeOrder: [Element] {
        sorted {
            RecipeIngredientOrder.precedes(
                amount: $0.amount,
                name: $0.ingredient.name,
                before: $1.amount,
                otherName: $1.ingredient.name
            )
        }
    }
}
