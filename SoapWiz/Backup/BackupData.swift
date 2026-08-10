import Foundation

/// A versioned, locale-independent snapshot of the entire SoapWiz store.
///
/// Entities reference each other by *array index* — the position of the related
/// entity in the corresponding top-level array — so the object graph can be
/// rebuilt on import without relying on user-entered values (names, badges)
/// being unique. Owned children (purchases, recipe line items, batch line items)
/// are nested under their parent.
struct BackupData: Codable {
    /// Bumped whenever the on-disk format changes in a way that needs migration.
    /// Imports reject any file whose `version` is newer than this.
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var settings: SettingsDTO
    var categories: [CategoryDTO]
    var providers: [ProviderDTO]
    var storageLocations: [StorageLocationDTO]
    var ingredients: [IngredientDTO]
    var recipes: [RecipeDTO]
    var batches: [BatchDTO]

    /// True when the snapshot holds nothing worth restoring. `settings` is excluded
    /// deliberately — it always exists, and a default pricing factor is not data the
    /// user would miss.
    var isEmpty: Bool {
        categories.isEmpty && providers.isEmpty && storageLocations.isEmpty
            && ingredients.isEmpty && recipes.isEmpty && batches.isEmpty
    }
}

extension BackupData {
    struct SettingsDTO: Codable {
        var pvpFactor: Double
    }

    struct CategoryDTO: Codable {
        var name: String
    }

    struct ProviderDTO: Codable {
        var name: String
        var website: String
        var notes: String
    }

    struct StorageLocationDTO: Codable {
        var name: String
        var locationDescription: String
    }

    struct IngredientDTO: Codable {
        var name: String
        var code: String
        var unit: String
        /// Optional so a file written before favourites existed still decodes; it
        /// restores to the schema default of `false`.
        var isFavorite: Bool?
        /// Index into `BackupData.categories`, or `nil` when uncategorised.
        var categoryIndex: Int?
        var lowStockThreshold: Double?
        var sapValue: Double?
        var kohSapValue: Double?
        var density: Double?
        var fattyAcidProfile: FattyAcidProfile?
        var purchases: [PurchaseDTO]
    }

    struct PurchaseDTO: Codable {
        /// Preserved so batch draw snapshots (`BatchPurchaseDraw.purchaseUUID`)
        /// still resolve back to their purchase after a round-trip.
        var uuid: UUID
        /// Index into `BackupData.providers`, or `nil`.
        var providerIndex: Int?
        /// Index into `BackupData.storageLocations`, or `nil`.
        var storageLocationIndex: Int?
        var dateOfPurchase: Date
        var quantity: Double
        var totalPrice: Double
        var badge: String
        var journalCode: String
        var expiryDate: Date?
        var openingDate: Date?
        var remainingAmount: Double
    }

    struct RecipeDTO: Codable {
        var name: String
        var desc: String
        /// Optional so a file written before favourites existed still decodes; it
        /// restores to the schema default of `false`.
        var isFavorite: Bool?
        var weightUnit: String
        var totalOilWeight: Double
        var oilWeightUnit: String
        var lyeType: String
        var lyePurity: Double
        var waterParts: Double
        var superFat: Double
        var fragrancePercentage: Double
        /// Optional so a file without the key still decodes. It restores to the
        /// schema default and the rows are stamped to match on load — the
        /// recipe-wide unit is authoritative, so a row's own unit is discarded
        /// rather than consulted.
        var fragranceUnit: String?
        var useHybrid: Bool
        var kohPercentage: Double
        var naohPercentage: Double
        var kohPurity: Double
        var naohPurity: Double
        var isCreamSoap: Bool
        var useCFM: Bool
        var cfmNeutralizer: String
        /// Index into `BackupData.ingredients`, or `nil`.
        var lyeIngredientIndex: Int?
        var kohLyeIngredientIndex: Int?
        var ingredients: [RecipeIngredientDTO]
        var products: [RecipeProductDTO]
    }

    struct RecipeIngredientDTO: Codable {
        /// Index into `BackupData.ingredients`. Required — a recipe line item
        /// always points at an ingredient.
        var ingredientIndex: Int
        var percentage: Double
        var role: String
        var additiveAmount: Double
        var additiveUnit: String
    }

    struct RecipeProductDTO: Codable {
        var size: Double
        var unitSymbol: String
    }

    struct BatchDTO: Codable {
        /// Index into `BackupData.recipes`, or `nil` when the source recipe was
        /// already deleted (the batch's `.nullify` link).
        var recipeIndex: Int?
        var recipeName: String
        var dateCreated: Date
        var batchCount: Int
        var totalCost: Double
        var lineItems: [BatchLineItemDTO]
    }

    struct BatchLineItemDTO: Codable {
        /// Index into `BackupData.ingredients`, or `nil` when the source
        /// ingredient was already deleted (the line item's `.nullify` link).
        var ingredientIndex: Int?
        var ingredientName: String
        var amountConsumed: Double
        var unit: String
        var cost: Double
        var draws: [BatchPurchaseDraw]
    }
}

/// Failure modes surfaced to the user when a backup file can't be imported.
enum BackupError: LocalizedError {
    /// The file was produced by a newer app version using a format this build
    /// doesn't understand.
    case unsupportedVersion(found: Int, supported: Int)
    /// The file isn't a valid SoapWiz backup (wrong format or corrupted).
    case malformedFile

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(found, supported):
            return "This backup was made with a newer version of SoapWiz "
                + "(format \(found), this app supports up to \(supported)). "
                + "Update the app and try again."
        case .malformedFile:
            return "This file isn’t a valid SoapWiz backup."
        }
    }
}
