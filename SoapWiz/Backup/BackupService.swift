import Foundation
import SwiftData

/// Serialises the whole SoapWiz store to a `BackupData` document and restores it
/// back, rebuilding all cross-entity relationships from index references.
///
/// Restore is **replace-all**: the store is wiped and rebuilt from the file, so a
/// backup is an exact restore rather than a merge. `AppSettings` is treated as a
/// singleton and is never duplicated.
@MainActor
enum BackupService {

    // MARK: - Export

    /// Reads the current store into a `BackupData` snapshot.
    static func makeBackup(from context: ModelContext) throws -> BackupData {
        let categories = try context.fetch(FetchDescriptor<IngredientCategory>())
        let providers = try context.fetch(FetchDescriptor<Provider>())
        let storageLocations = try context.fetch(FetchDescriptor<StorageLocation>())
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let collections = try context.fetch(FetchDescriptor<RecipeCollection>())

        let categoryIndex = indexMap(categories)
        let providerIndex = indexMap(providers)
        let storageIndex = indexMap(storageLocations)
        let ingredientIndex = indexMap(ingredients)
        let recipeIndex = indexMap(recipes)
        let collectionIndex = indexMap(collections)

        return BackupData(
            version: BackupData.currentVersion,
            exportedAt: .now,
            settings: BackupData.SettingsDTO(pvpFactor: AppSettings.resolve(in: context).pvpFactor),
            categories: categories.map { BackupData.CategoryDTO(name: $0.name) },
            providers: providers.map {
                BackupData.ProviderDTO(name: $0.name, website: $0.website, notes: $0.notes)
            },
            storageLocations: storageLocations.map {
                BackupData.StorageLocationDTO(name: $0.name, locationDescription: $0.locationDescription)
            },
            ingredients: ingredients.map {
                ingredientDTO($0, categoryIndex: categoryIndex, providerIndex: providerIndex, storageIndex: storageIndex)
            },
            recipes: recipes.map {
                recipeDTO($0, ingredientIndex: ingredientIndex, collectionIndex: collectionIndex)
            },
            batches: batches.map { batchDTO($0, recipeIndex: recipeIndex, ingredientIndex: ingredientIndex) },
            collections: collections.map {
                BackupData.RecipeCollectionDTO(name: $0.name, colorName: $0.colorName)
            }
        )
    }

    private static func ingredientDTO(
        _ ingredient: Ingredient,
        categoryIndex: [PersistentIdentifier: Int],
        providerIndex: [PersistentIdentifier: Int],
        storageIndex: [PersistentIdentifier: Int]
    ) -> BackupData.IngredientDTO {
        BackupData.IngredientDTO(
            name: ingredient.name,
            code: ingredient.code,
            unit: ingredient.unit,
            isFavorite: ingredient.isFavorite,
            categoryIndex: ingredient.category.flatMap { categoryIndex[$0.persistentModelID] },
            lowStockThreshold: ingredient.lowStockThreshold,
            sapValue: ingredient.sapValue,
            kohSapValue: ingredient.kohSapValue,
            density: ingredient.density,
            fattyAcidProfile: ingredient.fattyAcidProfile,
            purchases: ingredient.purchases
                .sorted { $0.dateOfPurchase < $1.dateOfPurchase }
                .map { purchase in
                    BackupData.PurchaseDTO(
                        uuid: purchase.uuid,
                        providerIndex: purchase.provider.flatMap { providerIndex[$0.persistentModelID] },
                        storageLocationIndex: purchase.storageLocation.flatMap { storageIndex[$0.persistentModelID] },
                        dateOfPurchase: purchase.dateOfPurchase,
                        quantity: purchase.quantity,
                        totalPrice: purchase.totalPrice,
                        badge: purchase.badge,
                        journalCode: purchase.journalCode,
                        expiryDate: purchase.expiryDate,
                        openingDate: purchase.openingDate,
                        remainingAmount: purchase.remainingAmount
                    )
                }
        )
    }

    private static func recipeDTO(
        _ recipe: Recipe,
        ingredientIndex: [PersistentIdentifier: Int],
        collectionIndex: [PersistentIdentifier: Int]
    ) -> BackupData.RecipeDTO {
        BackupData.RecipeDTO(
            name: recipe.name,
            desc: recipe.desc,
            isFavorite: recipe.isFavorite,
            imageData: recipe.imageData,
            weightUnit: recipe.weightUnit,
            totalOilWeight: recipe.totalOilWeight,
            oilWeightUnit: recipe.oilWeightUnit,
            lyeType: recipe.lyeType,
            lyePurity: recipe.lyePurity,
            waterParts: recipe.waterParts,
            superFat: recipe.superFat,
            fragrancePercentage: recipe.fragrancePercentage,
            fragranceUnit: recipe.fragranceUnit,
            useHybrid: recipe.useHybrid,
            kohPercentage: recipe.kohPercentage,
            naohPercentage: recipe.naohPercentage,
            kohPurity: recipe.kohPurity,
            naohPurity: recipe.naohPurity,
            isCreamSoap: recipe.isCreamSoap,
            useCFM: recipe.useCFM,
            cfmNeutralizer: recipe.cfmNeutralizer,
            lyeIngredientIndex: recipe.lyeIngredient.flatMap { ingredientIndex[$0.persistentModelID] },
            kohLyeIngredientIndex: recipe.kohLyeIngredient.flatMap { ingredientIndex[$0.persistentModelID] },
            // Sorted so the exported file is stable: the relationship array's
            // own order is not, and an unsorted export would differ between two
            // runs over an unchanged store.
            collectionIndices: recipe.collections
                .compactMap { collectionIndex[$0.persistentModelID] }
                .sorted(),
            ingredients: recipe.ingredients.compactMap { line in
                line.ingredient.flatMap { ingredientIndex[$0.persistentModelID] }.map { idx in
                    BackupData.RecipeIngredientDTO(
                        ingredientIndex: idx,
                        percentage: line.percentage,
                        role: line.role,
                        additiveAmount: line.additiveAmount,
                        additiveUnit: line.additiveUnit
                    )
                }
            },
            products: recipe.products.map {
                BackupData.RecipeProductDTO(size: $0.size, unitSymbol: $0.unitSymbol)
            }
        )
    }

    private static func batchDTO(
        _ batch: Batch,
        recipeIndex: [PersistentIdentifier: Int],
        ingredientIndex: [PersistentIdentifier: Int]
    ) -> BackupData.BatchDTO {
        BackupData.BatchDTO(
            recipeIndex: batch.recipe.flatMap { recipeIndex[$0.persistentModelID] },
            recipeName: batch.recipeName,
            dateCreated: batch.dateCreated,
            batchCount: batch.batchCount,
            totalCost: batch.totalCost,
            lineItems: batch.lineItems.map { item in
                BackupData.BatchLineItemDTO(
                    ingredientIndex: item.ingredient.flatMap { ingredientIndex[$0.persistentModelID] },
                    ingredientName: item.ingredientName,
                    amountConsumed: item.amountConsumed,
                    unit: item.unit,
                    cost: item.cost,
                    draws: item.draws
                )
            }
        )
    }

    // MARK: - Encoding

    static func encode(_ backup: BackupData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Decodes and validates a backup file. Throws `BackupError` for an
    /// unreadable file or an unsupported (newer) format version — and does so
    /// *before* any destructive restore touches the store.
    static func decode(_ data: Data) throws -> BackupData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: BackupData
        do {
            backup = try decoder.decode(BackupData.self, from: data)
        } catch {
            throw BackupError.malformedFile
        }
        guard backup.version <= BackupData.currentVersion else {
            throw BackupError.unsupportedVersion(found: backup.version, supported: BackupData.currentVersion)
        }
        return backup
    }

    // MARK: - Helpers

    /// Maps each model to its position in `models`, keyed by persistent ID so the
    /// lookup survives even when user-facing fields collide.
    private static func indexMap<T: PersistentModel>(_ models: [T]) -> [PersistentIdentifier: Int] {
        Dictionary(uniqueKeysWithValues: models.enumerated().map { ($1.persistentModelID, $0) })
    }
}
