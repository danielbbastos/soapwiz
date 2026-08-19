import Foundation
import SwiftData

@Model
final class Recipe {
    var name: String = ""
    var desc: String = ""
    var isFavorite: Bool = false

    /// The recipe's photo, already downscaled by `ImageDownscaler` before it is
    /// assigned. `.externalStorage` keeps it in a file beside the store rather
    /// than in the row, so fetching a list of recipes doesn't drag every photo
    /// into memory with it; CloudKit mirrors it as an asset for the same reason.
    @Attribute(.externalStorage) var imageData: Data?

    /// The list row's copy of `imageData`, derived from it on save and never set
    /// independently. Deliberately not external: it is small, and a row that had
    /// to fault in a file to draw its thumbnail would defeat the point of having
    /// one.
    var thumbnailData: Data?
    var weightUnit: String = "g"

    /// Raw value of `RecipeKind`. Stored as a `String` rather than the enum,
    /// matching `lyeType`, `fragranceUnit`, and `cfmNeutralizer` — SwiftData and
    /// CloudKit want a primitive here. Defaulted rather than optional so every
    /// recipe stored before the kind existed reads back as soap.
    var recipeKind: String = RecipeKind.soap.rawValue

    /// The weight the recipe's percentages resolve against. Named for the soap
    /// case, where the oils are the base, but a general recipe uses the same
    /// field as its plain total weight — a second weight property would mean two
    /// sources of truth and every calculator downstream having to pick.
    var totalOilWeight: Double = 0
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: Double = 99
    var waterParts: Double = 1.5
    var superFat: Double = 5
    var fragrancePercentage: Double = 3

    /// Recipe-wide unit for every fragrance row. Raw value of `FragranceUnit`.
    /// Fragrance rows ignore their own `additiveUnit`; this is the single source
    /// of truth.
    var fragranceUnit: String = FragranceUnit.percentOfOils.rawValue

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

    // Inverse and `.nullify` delete rule are declared on `Ingredient.recipesUsingAsLye`,
    // so a deleted ingredient drops this link instead of taking the recipe with it.
    var lyeIngredient: Ingredient?

    /// The KOH lye ingredient used by the hybrid path, so its cost can be priced
    /// separately from the NaOH `lyeIngredient`. Inverse and delete rule are
    /// declared on `Ingredient.recipesUsingAsKOHLye`.
    var kohLyeIngredient: Ingredient?

    /// Optional for CloudKit; read and write through `ingredients`. Neither name
    /// is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, originalName: "ingredients", inverse: \RecipeIngredient.recipe)
    var ingredientsStorage: [RecipeIngredient]? = []

    var ingredients: [RecipeIngredient] {
        get { ingredientsStorage ?? [] }
        set { ingredientsStorage = newValue }
    }

    /// Optional for CloudKit; read and write through `products`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, originalName: "products", inverse: \RecipeProduct.recipe)
    var productsStorage: [RecipeProduct]? = []

    var products: [RecipeProduct] {
        get { productsStorage ?? [] }
        set { productsStorage = newValue }
    }

    /// Themes this recipe is filed under. Many-to-many and `.nullify` on both
    /// sides — the inverse and delete rule are declared on
    /// `RecipeCollection.recipesStorage`, so deleting a collection unfiles the
    /// recipe rather than deleting it.
    ///
    /// Optional for CloudKit; read and write through `collections`. Neither name
    /// is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "collections")
    var collectionsStorage: [RecipeCollection]? = []

    var collections: [RecipeCollection] {
        get { collectionsStorage ?? [] }
        set { collectionsStorage = newValue }
    }

    /// Batches made from this recipe. Deleting the recipe nullifies each batch's
    /// back-link (`.nullify`) rather than deleting it — batch history is an
    /// immutable record that must outlive the recipe.
    ///
    /// Optional for CloudKit; read and write through `batches`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "batches", inverse: \Batch.recipe)
    var batchesStorage: [Batch]? = []

    var batches: [Batch] {
        get { batchesStorage ?? [] }
        set { batchesStorage = newValue }
    }

    init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}
