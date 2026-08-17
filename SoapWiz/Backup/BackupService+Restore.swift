import Foundation
import SwiftData

/// Rebuilding the store from a `BackupData` snapshot. Split from the export
/// side so neither half of the round trip has to be read to follow the other.
@MainActor
extension BackupService {

    /// Wipes the store and rebuilds it from `backup`. Cross-entity references are
    /// resolved from the file's index references; out-of-range indices are
    /// dropped rather than crashing.
    static func restore(_ backup: BackupData, into context: ModelContext) throws {
        guard backup.version <= BackupData.currentVersion else {
            throw BackupError.unsupportedVersion(found: backup.version, supported: BackupData.currentVersion)
        }

        do {
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
            let collections = (backup.collections ?? []).map { dto -> RecipeCollection in
                let collection = RecipeCollection(name: dto.name, colorName: dto.colorName)
                context.insert(collection)
                return collection
            }
            let ingredients = backup.ingredients.map {
                restoreIngredient($0, categories: categories, providers: providers, storageLocations: storageLocations, into: context)
            }
            let recipes = backup.recipes.map {
                restoreRecipe($0, ingredients: ingredients, collections: collections, into: context)
            }
            for dto in backup.batches {
                restoreBatch(dto, recipes: recipes, ingredients: ingredients, into: context)
            }

            AppSettings.resolve(in: context).pvpFactor = backup.settings.pvpFactor

            try context.save()
        } catch {
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
        ingredient.isFavorite = dto.isFavorite ?? false
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
        collections: [RecipeCollection],
        into context: ModelContext
    ) -> Recipe {
        let recipe = Recipe(name: dto.name, desc: dto.desc)
        recipe.isFavorite = dto.isFavorite ?? false
        recipe.imageData = dto.imageData
        // Rebuilt rather than restored: the file carries only the display image,
        // and a thumbnail is a few milliseconds of work per photographed recipe.
        recipe.thumbnailData = dto.imageData.flatMap(ImageDownscaler.thumbnail(from:))
        recipe.weightUnit = dto.weightUnit
        recipe.totalOilWeight = dto.totalOilWeight
        recipe.oilWeightUnit = dto.oilWeightUnit
        recipe.lyeType = dto.lyeType
        recipe.lyePurity = dto.lyePurity
        recipe.waterParts = dto.waterParts
        recipe.superFat = dto.superFat
        recipe.fragrancePercentage = dto.fragrancePercentage
        recipe.fragranceUnit = dto.fragranceUnit ?? FragranceUnit.percentOfOils.rawValue
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
        recipe.collections = (dto.collectionIndices ?? []).compactMap { element(collections, at: $0) }
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
        try deleteAll(RecipeCollection.self, in: context)
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
