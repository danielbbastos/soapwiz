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

    /// When `true` the recipe uses a KOH + NaOH blend (`kohPercentage` /
    /// `naohPercentage`, each with its own purity) instead of the single-lye
    /// path driven by `lyeType` / `lyePurity`.
    var useHybrid: Bool = false
    var kohPercentage: Double = 90
    var naohPercentage: Double = 10
    var kohPurity: Double = 90
    var naohPurity: Double = 99

    @Relationship(deleteRule: .nullify)
    var lyeIngredient: Ingredient?

    /// The KOH lye ingredient used by the hybrid path, so its cost can be priced
    /// separately from the NaOH `lyeIngredient`.
    @Relationship(deleteRule: .nullify)
    var kohLyeIngredient: Ingredient?

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
