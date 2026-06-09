import SwiftData

@Model
final class Recipe {
    var name: String = ""
    var desc: String = ""
    var weightUnit: String = "g"
    var totalOilWeight: Double = 0
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: Double = 99
    var waterParts: Double = 1.5
    var superFat: Double = 5
    var fragrancePercentage: Double = 3

    @Relationship(deleteRule: .nullify)
    var lyeIngredient: Ingredient?

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeProduct.recipe)
    var products: [RecipeProduct] = []

    /// Batches made from this recipe. Deleting the recipe nullifies each batch's
    /// back-link (`.nullify`) rather than deleting it — batch history is an
    /// immutable record that must outlive the recipe.
    @Relationship(deleteRule: .nullify, inverse: \Batch.recipe)
    var batches: [Batch] = []

    init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}
