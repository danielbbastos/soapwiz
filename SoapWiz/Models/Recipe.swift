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

    /// Cream-soap method: doesn't change the lye math, only appends recommended
    /// additions (extra water, glycerine) scaled to the oil weight. Independent of
    /// the auto-classified `SoapType.cream` and may be combined with `useCFM`.
    var isCreamSoap: Bool = false

    /// Catherine Failor liquid-soap method. When active (and the soap isn't a
    /// solid bar) the lye is taken at 0% superfat + 10% excess and a boric-acid
    /// or borax neutraliser solution is recommended. `cfmNeutralizer` is the
    /// `CFMNeutralizer` raw value ("boric" / "borax").
    var useCFM: Bool = false
    var cfmNeutralizer: String = CFMNeutralizer.boricAcid.rawValue

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
