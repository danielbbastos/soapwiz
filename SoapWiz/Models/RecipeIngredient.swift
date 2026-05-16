import SwiftData

@Model
final class RecipeIngredient {
    var recipe: Recipe?
    var ingredient: Ingredient
    var percentage: Double

    init(ingredient: Ingredient, percentage: Double = 0) {
        self.ingredient = ingredient
        self.percentage = percentage
    }
}
