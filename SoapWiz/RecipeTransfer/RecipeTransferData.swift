import Foundation

/// A versioned, locale-independent payload holding one or more recipes and the
/// ingredient chemistry they depend on.
///
/// This is the exact counterpart to `RecipeImportDraft`. That type models what a
/// language model can be trusted to read off a page; this one models what
/// SoapWiz itself knows, and it round-trips every field the recipe form owns.
/// The two never meet: an exact payload routed through the draft would silently
/// lose the hybrid lye split, the cream-soap and CFM settings, the recipe kind,
/// the fragrance unit and the products.
///
/// Carried two ways — as a `.soapwizrecipe` file, and as a marker line appended
/// to the text "Copy Recipe" puts on the clipboard. The format is the same
/// either way; only the envelope differs. See `RecipeTransferMarker`.
struct RecipeTransferData: Codable, Equatable {
    /// Bumped whenever the format changes in a way an older build would read
    /// wrongly. Decoding rejects any payload whose `version` is newer than this
    /// rather than reading part of it.
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date

    /// Every ingredient the recipes reference, once each. Pooled rather than
    /// repeated per recipe: fifteen recipes from one library name olive oil
    /// fifteen times, and its fatty-acid profile is the largest thing in the
    /// payload.
    var ingredients: [RecipeTransferIngredient]
    var recipes: [RecipeTransferRecipe]

    init(
        version: Int = RecipeTransferData.currentVersion,
        exportedAt: Date,
        ingredients: [RecipeTransferIngredient],
        recipes: [RecipeTransferRecipe]
    ) {
        self.version = version
        // Truncated to the resolution the format actually stores. ISO-8601
        // writes whole seconds, so a payload built from `.now` would not equal
        // itself after a round trip — and "decodes to what was encoded" is the
        // one property every test here rests on. Not date arithmetic: this
        // drops a fraction the format has nowhere to put.
        self.exportedAt = Date(timeIntervalSince1970: exportedAt.timeIntervalSince1970.rounded(.down))
        self.ingredients = ingredients
        self.recipes = recipes
    }

    /// Whether every line item points at an ingredient that exists in the pool.
    ///
    /// Checked before anything reads the payload, because every line item
    /// resolves its ingredient by subscripting `ingredients` and an index from a
    /// truncated or hand-edited file would trap. A payload that fails this is
    /// malformed, not partially usable.
    var hasResolvableIngredientIndices: Bool {
        let range = ingredients.indices
        return recipes.allSatisfy { recipe in
            recipe.ingredients.allSatisfy { range.contains($0.ingredientIndex) }
        }
    }
}

/// One ingredient's identity and the chemistry a recipe needs to stand alone on
/// a device that has never seen it.
///
/// `Ingredient` has no `uuid`, so `name` is what resolves this against the
/// recipient's inventory. On the sender's own device every name matches their
/// own row, which is what makes a same-device round trip exact.
///
/// Deliberately absent: photos, purchases, prices, stock, category and code.
/// A recipe needs to know what an oil *is*, not what the sender paid for it or
/// how much is left in the bottle.
struct RecipeTransferIngredient: Codable, Equatable {
    var name: String
    var unit: String
    var sapValue: Double?
    var kohSapValue: Double?
    var density: Double?
    var fattyAcidProfile: FattyAcidProfile?
}

/// One recipe, carrying every field `RecipeFormViewModel` owns.
///
/// Photos are excluded from the format entirely, so there is no field here to
/// carry one. A photo of a finished bar on a kitchen counter is personal in a
/// way a formula is not, and a share must never carry one without the sender
/// having thought about it. The recipient adds their own.
///
/// Also absent: `isFavorite`, and the `lyeIngredient` / `kohLyeIngredient` used
/// to cost the lye. The sender's costing ingredient means nothing on another
/// device, and the recipient's form resolves its own through
/// `resolveDefaultLyeIngredient(from:)`.
struct RecipeTransferRecipe: Codable, Equatable {
    var name: String
    var desc: String

    /// Raw value of `RecipeKind`.
    var recipeKind: String
    var weightUnit: String
    var totalOilWeight: Double
    var oilWeightUnit: String
    var lyeType: String
    var lyePurity: Double
    var waterParts: Double
    var superFat: Double
    var useHybrid: Bool
    var kohPercentage: Double
    var naohPercentage: Double
    var kohPurity: Double
    var naohPurity: Double
    var isCreamSoap: Bool
    var useCFM: Bool

    /// Raw value of `CFMNeutralizer`.
    var cfmNeutralizer: String
    var fragrancePercentage: Double

    /// Raw value of `FragranceUnit`. Recipe-wide: the line items' own units are
    /// not consulted for fragrance rows.
    var fragranceUnit: String

    /// Collections this recipe is filed under, by name.
    ///
    /// Names rather than indices into a pool, which is what `BackupData` would
    /// do. A backup rebuilds an object graph and needs identity; here a
    /// collection is only ever *matched* against one the recipient already has
    /// and is never created, so the name is the reference. An index would add a
    /// decode step that can fail for nothing in return.
    var collectionNames: [String]
    var ingredients: [RecipeTransferLineItem]
    var products: [RecipeTransferProduct]

    var kind: RecipeKind { RecipeKind.resolve(recipeKind) }
}

/// One recipe line item. `ingredientIndex` points into
/// `RecipeTransferData.ingredients`.
struct RecipeTransferLineItem: Codable, Equatable {
    var ingredientIndex: Int

    /// Raw value of `RecipeIngredientRole`.
    var role: String

    /// The oil share. Zero for additive and fragrance rows, which carry their
    /// amount in `additiveAmount` — the same split `RecipeIngredient` uses.
    var percentage: Double
    var additiveAmount: Double
    var additiveUnit: String
}

struct RecipeTransferProduct: Codable, Equatable {
    var size: Double
    var unitSymbol: String
}

/// Failure modes surfaced to the user when a shared recipe can't be read.
enum RecipeTransferError: LocalizedError, Equatable {
    /// Written by a newer app version using a format this build doesn't
    /// understand. Rejected outright rather than read in part: a recipe missing
    /// the fields this build can't see would calculate a different lye weight
    /// without saying so.
    case unsupportedVersion(found: Int, supported: Int)

    /// Not a SoapWiz recipe file, or damaged in transit.
    case malformedFile

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(found, supported):
            return "This recipe was shared from a newer version of SoapWiz "
                + "(format \(found), this app supports up to \(supported)). "
                + "Update the app and try again."
        case .malformedFile:
            return "This file isn’t a SoapWiz recipe, or it was damaged on the way here."
        }
    }
}
