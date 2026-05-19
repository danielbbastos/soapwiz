import SwiftData

@Model
final class Recipe {
    var name: String
    var desc: String

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeProduct.recipe)
    var products: [RecipeProduct] = []

    init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}
