import SwiftData

enum RecipeIngredientRole: String {
    case oil, additive, fragrance
}

@Model
final class RecipeIngredient {
    var recipe: Recipe?

    // Inverse and `.cascade` delete rule are declared on `Ingredient.recipeIngredients`.
    // Optional because CloudKit requires it: a sync race can deliver this row before
    // the ingredient it points at, so readers must tolerate a nil ingredient.
    var ingredient: Ingredient?
    var percentage: Double = 0
    var role: String = RecipeIngredientRole.oil.rawValue
    var additiveAmount: Double = 0
    var additiveUnit: String = "g"

    var ingredientRole: RecipeIngredientRole {
        RecipeIngredientRole(rawValue: role) ?? .oil
    }

    init(ingredient: Ingredient?, percentage: Double = 0, role: RecipeIngredientRole = .oil) {
        self.ingredient = ingredient
        self.percentage = percentage
        self.role = role.rawValue
    }
}
