import SwiftUI
import SwiftData

/// The ingredient rows the recipe screen and the Create-Batch sheet resolve
/// their lye and neutraliser defaults against. Kept out of `RecipeDetailView`
/// itself so that file stays under the length limit.
extension RecipeDetailView {
    /// Hidden lyes are excluded, for the reason given on `RecipeFormView`'s copy.
    /// The batch sheet puts this recipe's own lye back.
    static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    /// Additives the neutraliser default is resolved against, hidden rows
    /// excluded for the same reason the lyes are.
    static let additivesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.additives
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()
}
