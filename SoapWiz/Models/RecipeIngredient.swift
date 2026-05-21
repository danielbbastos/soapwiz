import SwiftData

enum RecipeIngredientRole: String {
    case oil, additive, fragrance
}

@Model
final class RecipeIngredient {
    var recipe: Recipe?
    var ingredient: Ingredient
    var percentage: Double
    var role: String = RecipeIngredientRole.oil.rawValue
    var additiveAmount: Double = 0
    var additiveUnit: String = "g"

    var ingredientRole: RecipeIngredientRole {
        RecipeIngredientRole(rawValue: role) ?? .oil
    }

    init(ingredient: Ingredient, percentage: Double = 0, role: RecipeIngredientRole = .oil) {
        self.ingredient = ingredient
        self.percentage = percentage
        self.role = role.rawValue
    }
}
