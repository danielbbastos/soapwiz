import SwiftUI
import SwiftData

/// The ingredient rows the Create-Batch sheet resolves its lye and neutraliser
/// defaults against. Kept out of `RecipeDetailView` itself so that file stays
/// under the length limit.
extension RecipeDetailView {
    /// Hidden lyes are excluded, for the reason given on `RecipeFormView`'s copy.
    /// `lyeCandidates` puts this recipe's own lye back for the batch sheet.
    static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    /// Additives the batch sheet resolves the neutraliser default against, hidden
    /// rows excluded for the same reason the lyes are.
    static let additivesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.additives
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    /// What the batch sheet offers: the visible lyes, plus this recipe's own, which
    /// may have been hidden since it was chosen.
    var lyeCandidates: [Ingredient] {
        RecipeFormViewModel.lyeCandidates(
            visible: lyeIngredients,
            keeping: [recipe.lyeIngredient, recipe.kohLyeIngredient]
        )
    }

    /// The additives the batch sheet resolves the neutraliser from, plus this
    /// recipe's own neutraliser even if it has since been hidden.
    var neutralizerCandidates: [Ingredient] {
        RecipeFormViewModel.neutralizerCandidates(
            visible: additiveIngredients,
            keeping: [recipe.neutralizerIngredient]
        )
    }
}
