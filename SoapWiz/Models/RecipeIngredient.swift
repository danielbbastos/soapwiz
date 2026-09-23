import SwiftData

enum RecipeIngredientRole: String {
    case oil, additive, fragrance
}

@Model
final class RecipeIngredient {
    var recipe: Recipe?

    // Inverse and `.nullify` delete rule are declared on `Ingredient.recipeIngredients`.
    // Optional because CloudKit requires it: a sync race can deliver this row before
    // the ingredient it points at, so readers must tolerate a nil ingredient.
    var ingredient: Ingredient?
    /// The library slug of `ingredient`, kept so `IngredientLinkRepair` can
    /// re-attach this row if a sync race detaches it. Empty for a user-created
    /// ingredient, which the duplicate merge never deletes.
    var ingredientSlug: String = ""
    var percentage: Double = 0
    var role: String = RecipeIngredientRole.oil.rawValue
    var additiveAmount: Double = 0
    var additiveUnit: String = "g"

    var ingredientRole: RecipeIngredientRole {
        RecipeIngredientRole(rawValue: role) ?? .oil
    }

    init(ingredient: Ingredient?, percentage: Double = 0, role: RecipeIngredientRole = .oil) {
        self.ingredient = ingredient
        self.ingredientSlug = ingredient?.librarySlug ?? ""
        self.percentage = percentage
        self.role = role.rawValue
    }
}
