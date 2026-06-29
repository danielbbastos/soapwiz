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

        let categoryIndex = indexMap(categories)
        let providerIndex = indexMap(providers)
        let storageIndex = indexMap(storageLocations)
        let ingredientIndex = indexMap(ingredients)
        let recipeIndex = indexMap(recipes)

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
            recipes: recipes.map { recipeDTO($0, ingredientIndex: ingredientIndex) },
            batches: batches.map { batchDTO($0, recipeIndex: recipeIndex, ingredientIndex: ingredientIndex) }
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
        ingredientIndex: [PersistentIdentifier: Int]
    ) -> BackupData.RecipeDTO {
        BackupData.RecipeDTO(
            name: recipe.name,
            desc: recipe.desc,
            weightUnit: recipe.weightUnit,
            totalOilWeight: recipe.totalOilWeight,
            oilWeightUnit: recipe.oilWeightUnit,
            lyeType: recipe.lyeType,
            lyePurity: recipe.lyePurity,
            waterParts: recipe.waterParts,
            superFat: recipe.superFat,
            fragrancePercentage: recipe.fragrancePercentage,
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
            ingredients: recipe.ingredients.compactMap { line in
                ingredientIndex[line.ingredient.persistentModelID].map { idx in
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

    // MARK: - Restore

    /// Wipes the store and rebuilds it from `backup`. Cross-entity references are
    /// resolved from the file's index references; out-of-range indices are
    /// dropped rather than crashing.
    static func restore(_ backup: BackupData, into context: ModelContext) throws {
        guard backup.version <= BackupData.currentVersion else {
            throw BackupError.unsupportedVersion(found: backup.version, supported: BackupData.currentVersion)
        }

        try wipe(context)

        let categories = backup.categories.map { dto -> IngredientCategory in
            let category = IngredientCategory(name: dto.name)
            context.insert(category)
            return category
        }
        let providers = backup.providers.map { dto -> Provider in
            let provider = Provider(name: dto.name, website: dto.website, notes: dto.notes)
            context.insert(provider)
            return provider
        }
        let storageLocations = backup.storageLocations.map { dto -> StorageLocation in
            let location = StorageLocation(name: dto.name, locationDescription: dto.locationDescription)
            context.insert(location)
            return location
        }
        let ingredients = backup.ingredients.map {
            restoreIngredient($0, categories: categories, providers: providers, storageLocations: storageLocations, into: context)
        }
        let recipes = backup.recipes.map { restoreRecipe($0, ingredients: ingredients, into: context) }
        for dto in backup.batches {
            restoreBatch(dto, recipes: recipes, ingredients: ingredients, into: context)
        }

        // Reuse the singleton rather than inserting a second settings record.
        AppSettings.resolve(in: context).pvpFactor = backup.settings.pvpFactor

        do {
            try context.save()
        } catch {
            // The wipe + rebuild left the context dirty. Without a rollback,
            // SwiftData's auto-save on backgrounding could commit this partial
            // state and permanently destroy the original data. Reset to the
            // last persisted snapshot so the on-disk store stays authoritative.
            context.rollback()
            throw error
        }
    }

    private static func restoreIngredient(
        _ dto: BackupData.IngredientDTO,
        categories: [IngredientCategory],
        providers: [Provider],
        storageLocations: [StorageLocation],
        into context: ModelContext
    ) -> Ingredient {
        let ingredient = Ingredient(name: dto.name, unit: dto.unit)
        ingredient.code = dto.code
        ingredient.category = element(categories, at: dto.categoryIndex)
        ingredient.lowStockThreshold = dto.lowStockThreshold
        ingredient.sapValue = dto.sapValue
        ingredient.kohSapValue = dto.kohSapValue
        ingredient.density = dto.density
        ingredient.fattyAcidProfile = dto.fattyAcidProfile
        context.insert(ingredient)

        for purchaseDTO in dto.purchases {
            let purchase = IngredientPurchase(
                provider: element(providers, at: purchaseDTO.providerIndex),
                dateOfPurchase: purchaseDTO.dateOfPurchase,
                quantity: purchaseDTO.quantity,
                totalPrice: purchaseDTO.totalPrice,
                badge: purchaseDTO.badge,
                journalCode: purchaseDTO.journalCode,
                expiryDate: purchaseDTO.expiryDate,
                openingDate: purchaseDTO.openingDate,
                storageLocation: element(storageLocations, at: purchaseDTO.storageLocationIndex)
            )
            purchase.uuid = purchaseDTO.uuid
            purchase.remainingAmount = purchaseDTO.remainingAmount
            purchase.ingredient = ingredient
            context.insert(purchase)
        }
        return ingredient
    }

    private static func restoreRecipe(
        _ dto: BackupData.RecipeDTO,
        ingredients: [Ingredient],
        into context: ModelContext
    ) -> Recipe {
        let recipe = Recipe(name: dto.name, desc: dto.desc)
        recipe.weightUnit = dto.weightUnit
        recipe.totalOilWeight = dto.totalOilWeight
        recipe.oilWeightUnit = dto.oilWeightUnit
        recipe.lyeType = dto.lyeType
        recipe.lyePurity = dto.lyePurity
        recipe.waterParts = dto.waterParts
        recipe.superFat = dto.superFat
        recipe.fragrancePercentage = dto.fragrancePercentage
        recipe.useHybrid = dto.useHybrid
        recipe.kohPercentage = dto.kohPercentage
        recipe.naohPercentage = dto.naohPercentage
        recipe.kohPurity = dto.kohPurity
        recipe.naohPurity = dto.naohPurity
        recipe.isCreamSoap = dto.isCreamSoap
        recipe.useCFM = dto.useCFM
        recipe.cfmNeutralizer = dto.cfmNeutralizer
        recipe.lyeIngredient = element(ingredients, at: dto.lyeIngredientIndex)
        recipe.kohLyeIngredient = element(ingredients, at: dto.kohLyeIngredientIndex)
        context.insert(recipe)

        for lineDTO in dto.ingredients {
            guard ingredients.indices.contains(lineDTO.ingredientIndex) else { continue }
            let line = RecipeIngredient(
                ingredient: ingredients[lineDTO.ingredientIndex],
                percentage: lineDTO.percentage,
                role: RecipeIngredientRole(rawValue: lineDTO.role) ?? .oil
            )
            line.additiveAmount = lineDTO.additiveAmount
            line.additiveUnit = lineDTO.additiveUnit
            line.recipe = recipe
            context.insert(line)
        }
        for productDTO in dto.products {
            let product = RecipeProduct(size: productDTO.size, unitSymbol: productDTO.unitSymbol)
            product.recipe = recipe
            context.insert(product)
        }
        return recipe
    }

    private static func restoreBatch(
        _ dto: BackupData.BatchDTO,
        recipes: [Recipe],
        ingredients: [Ingredient],
        into context: ModelContext
    ) {
        let batch = Batch(
            recipe: element(recipes, at: dto.recipeIndex),
            recipeName: dto.recipeName,
            dateCreated: dto.dateCreated,
            batchCount: dto.batchCount,
            totalCost: dto.totalCost
        )
        context.insert(batch)

        for itemDTO in dto.lineItems {
            let item = BatchLineItem(
                ingredient: element(ingredients, at: itemDTO.ingredientIndex),
                ingredientName: itemDTO.ingredientName,
                amountConsumed: itemDTO.amountConsumed,
                unit: itemDTO.unit,
                cost: itemDTO.cost,
                draws: itemDTO.draws
            )
            item.batch = batch
            context.insert(item)
        }
    }

    // MARK: - Helpers

    /// Maps each model to its position in `models`, keyed by persistent ID so the
    /// lookup survives even when user-facing fields collide.
    private static func indexMap<T: PersistentModel>(_ models: [T]) -> [PersistentIdentifier: Int] {
        Dictionary(uniqueKeysWithValues: models.enumerated().map { ($1.persistentModelID, $0) })
    }

    /// Safe index lookup: returns `nil` for a `nil` or out-of-range index.
    private static func element<T>(_ array: [T], at index: Int?) -> T? {
        guard let index, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Deletes every record so the store can be rebuilt from the backup.
    ///
    /// Objects are removed one at a time (rather than via a batch
    /// `delete(model:)`) because batch deletes bypass the cascade/nullify
    /// relationship rules and trip the mandatory-inverse constraints between
    /// batches and their line items. Deleting the owners individually lets
    /// SwiftData cascade to the owned children (purchases, line items, recipe
    /// line items) the same way the app does.
    private static func wipe(_ context: ModelContext) throws {
        try deleteAll(Batch.self, in: context)
        try deleteAll(Recipe.self, in: context)
        try deleteAll(Ingredient.self, in: context)
        try deleteAll(IngredientCategory.self, in: context)
        try deleteAll(Provider.self, in: context)
        try deleteAll(StorageLocation.self, in: context)
        try deleteAll(AppSettings.self, in: context)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }
}
