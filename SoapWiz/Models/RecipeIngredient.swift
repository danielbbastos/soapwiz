import SwiftData

@Model
final class RecipeIngredient {
    var recipe: Recipe?
    var ingredient: Ingredient
    var percentage: Double
    var role: String = "oil"
    var additiveAmount: Double = 0
    var additiveUnit: String = "g"

    init(ingredient: Ingredient, percentage: Double = 0, role: String = "oil") {
        self.ingredient = ingredient
        self.percentage = percentage
        self.role = role
    }
}
