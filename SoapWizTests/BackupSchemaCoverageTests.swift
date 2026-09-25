import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Every stored property in the app's schema must be either carried by the
/// backup file or left out on purpose (SW-186). A recipe's neutraliser was
/// added to the model but never to the backup, and restores silently dropped
/// it; a new property now fails here until someone decides which it is.
@Suite("Backup – schema coverage")
@MainActor
struct BackupSchemaCoverageTests {

    /// Per model: properties the backup carries, possibly under another name
    /// (a relationship becomes an index, owned children are nested).
    private static let backedUp: [String: Set<String>] = [
        "AppSettings": ["pvpFactor", "expiryNotificationsEnabled", "tracksInventory", "currencyCode"],
        "Batch": ["recipe", "recipeName", "dateCreated", "batchCount", "totalCost", "tracksInventory", "lineItemsStorage"],
        "BatchLineItem": ["ingredient", "ingredientName", "amountConsumed", "unit", "cost", "draws"],
        "Ingredient": [
            "name", "code", "category", "unit", "isFavorite", "uuid", "librarySlug", "hasCustomChemistry",
            "isHidden", "imageData", "avatarColorName", "lowStockThreshold", "sapValue", "kohSapValue",
            "density", "fattyAcidProfile", "purchasesStorage"
        ],
        "IngredientCategory": ["name"],
        "IngredientPurchase": [
            "uuid", "provider", "dateOfPurchase", "quantity", "totalPrice", "badge", "journalCode",
            "expiryDate", "openingDate", "remainingAmount", "storageLocation"
        ],
        "Provider": ["name", "website", "notes"],
        "Recipe": [
            "uuid", "name", "desc", "isFavorite", "createdAt", "imageData", "weightUnit", "recipeKind",
            "totalOilWeight", "oilWeightUnit", "lyeType", "lyePurity", "waterParts", "superFat",
            "fragrancePercentage", "fragranceUnit", "useHybrid", "kohPercentage", "naohPercentage",
            "kohPurity", "naohPurity", "isCreamSoap", "useCFM", "cfmNeutralizer", "lyeIngredient",
            "kohLyeIngredient", "neutralizerIngredient", "ingredientsStorage", "productsStorage",
            "collectionsStorage"
        ],
        "RecipeCollection": ["name", "colorName"],
        "RecipeIngredient": ["ingredient", "percentage", "role", "additiveAmount", "additiveUnit"],
        "RecipeProduct": ["size", "unitSymbol"],
        "StorageLocation": ["name", "locationDescription"]
    ]

    /// Per model: properties the backup leaves out, and why.
    private static let excluded: [String: [String: String]] = [
        "AppSettings": ["uuid": "a singleton; restore resolves a fresh row"],
        "Batch": [:],
        "BatchLineItem": ["batch": "the inverse of nesting under the batch"],
        "Ingredient": [
            "thumbnailData": "rebuilt from imageData on restore",
            "recipeIngredientsStorage": "inverse, rebuilt from the recipe side",
            "batchLineItemsStorage": "inverse, rebuilt from the batch side",
            "recipesUsingAsLyeStorage": "inverse of Recipe.lyeIngredient",
            "recipesUsingAsKOHLyeStorage": "inverse of Recipe.kohLyeIngredient",
            "recipesUsingAsNeutralizerStorage": "inverse of Recipe.neutralizerIngredient"
        ],
        "IngredientCategory": [
            "uuid": "restore mints a fresh identity; the duplicate merge matches categories by name",
            "ingredientsStorage": "inverse, rebuilt from the ingredient side"
        ],
        "IngredientPurchase": [
            "ingredient": "the inverse of nesting under the ingredient",
            "ingredientSlug": "set from the restored ingredient by attach(to:) / RecipeIngredient.init"
        ],
        "Provider": [
            "uuid": "restore mints a fresh identity",
            "purchasesStorage": "inverse, rebuilt from the purchase side"
        ],
        "Recipe": [
            "thumbnailData": "rebuilt from imageData on restore",
            "batchesStorage": "inverse, rebuilt from the batch side"
        ],
        "RecipeCollection": [
            "uuid": "restore mints a fresh identity",
            "recipesStorage": "inverse, rebuilt from the recipe side"
        ],
        "RecipeIngredient": [
            "recipe": "the inverse of nesting under the recipe",
            "ingredientSlug": "set from the restored ingredient by attach(to:) / RecipeIngredient.init"
        ],
        "RecipeProduct": ["recipe": "the inverse of nesting under the recipe"],
        "StorageLocation": [
            "uuid": "restore mints a fresh identity",
            "purchasesStorage": "inverse, rebuilt from the purchase side"
        ]
    ]

    @Test func everyModel_IsAccountedFor() {
        let models = Set(ModelContainerFactory.schema.entities.map(\.name))

        #expect(models == Set(Self.backedUp.keys))
        #expect(models == Set(Self.excluded.keys))
    }

    @Test(arguments: ModelContainerFactory.schema.entities.map(\.name))
    func everyStoredProperty_IsBackedUpOrExcludedOnPurpose(_ model: String) {
        let stored = Set(ModelContainerFactory.schema.entities.first { $0.name == model }?.properties.map(\.name) ?? [])
        let backedUp = Self.backedUp[model] ?? []
        let excluded = Set((Self.excluded[model] ?? [:]).keys)

        let unaccounted = stored.subtracting(backedUp).subtracting(excluded)
        let stale = backedUp.union(excluded).subtracting(stored)
        #expect(unaccounted.isEmpty, "Not in the backup: \(unaccounted.sorted())")
        #expect(stale.isEmpty, "No longer in the model: \(stale.sorted())")
        #expect(backedUp.isDisjoint(with: excluded))
    }
}
