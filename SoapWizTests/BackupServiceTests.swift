import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BackupService", .serialized)
@MainActor
struct BackupServiceTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            StorageLocation.self, Provider.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Batch.self, BatchLineItem.self, AppSettings.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// Builds a fully-connected store: an oil with a category, two purchases
    /// (each with a provider and storage location), a recipe referencing the oil
    /// as both a line item and lye, with one product, and a batch whose line item
    /// draws from a known purchase. Returns the original purchase UUID so draw
    /// re-linking can be verified after a round-trip.
    @discardableResult
    private func seedFullGraph(_ ctx: ModelContext) -> UUID {
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let provider = Provider(name: "Acme", website: "acme.test", notes: "fast")
        ctx.insert(provider)
        let location = StorageLocation(name: "Shelf A", locationDescription: "top")
        ctx.insert(location)

        let oil = makeOil(ctx, category: category)
        let firstPurchase = makePurchases(ctx, oil: oil, provider: provider, location: location)
        let recipe = makeRecipe(ctx, oil: oil)
        makeBatch(ctx, recipe: recipe, oil: oil, drawnPurchase: firstPurchase)

        AppSettings.resolve(in: ctx).pvpFactor = 4.25
        try? ctx.save()
        return firstPurchase.uuid
    }

    private func makeOil(_ ctx: ModelContext, category: IngredientCategory) -> Ingredient {
        let oil = Ingredient(name: "Olive Oil", category: category, unit: "g")
        oil.code = "OO1"
        oil.sapValue = 0.1345
        oil.density = 0.915
        oil.lowStockThreshold = 100
        oil.fattyAcidProfile = FattyAcidProfile(palmitic: 14, oleic: 69, linoleic: 12)
        ctx.insert(oil)
        return oil
    }

    /// Inserts two purchases for `oil` and returns the first (with 750 g remaining).
    private func makePurchases(
        _ ctx: ModelContext, oil: Ingredient, provider: Provider, location: StorageLocation
    ) -> IngredientPurchase {
        let firstPurchase = IngredientPurchase(
            provider: provider, dateOfPurchase: .now, quantity: 1000, totalPrice: 8.5,
            badge: "LOT1", journalCode: "J1", expiryDate: nil, openingDate: nil,
            storageLocation: location
        )
        firstPurchase.remainingAmount = 750
        firstPurchase.ingredient = oil
        ctx.insert(firstPurchase)

        let secondPurchase = IngredientPurchase(
            provider: provider, dateOfPurchase: .now, quantity: 500, totalPrice: 5,
            badge: "LOT2", journalCode: "J2", expiryDate: nil, openingDate: nil,
            storageLocation: location
        )
        secondPurchase.ingredient = oil
        ctx.insert(secondPurchase)
        return firstPurchase
    }

    private func makeRecipe(_ ctx: ModelContext, oil: Ingredient) -> Recipe {
        let recipe = Recipe(name: "Castile", desc: "100% olive")
        recipe.totalOilWeight = 1000
        recipe.superFat = 7
        recipe.fragranceUnit = FragranceUnit.percentOfFragrances.rawValue
        recipe.lyeIngredient = oil
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: oil, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        let product = RecipeProduct(size: 100, unitSymbol: "g")
        product.recipe = recipe
        ctx.insert(product)
        return recipe
    }

    private func makeBatch(
        _ ctx: ModelContext, recipe: Recipe, oil: Ingredient, drawnPurchase: IngredientPurchase
    ) {
        let batch = Batch(recipe: recipe, recipeName: recipe.name, batchCount: 2, totalCost: 6.4)
        ctx.insert(batch)
        let draw = BatchPurchaseDraw(
            purchaseUUID: drawnPurchase.uuid, purchaseBadge: "LOT1",
            amountDrawn: 250, pricePerUnit: 0.0085, cost: 2.125
        )
        let item = BatchLineItem(
            ingredient: oil, ingredientName: oil.name, amountConsumed: 250,
            unit: "g", cost: 2.125, draws: [draw]
        )
        item.batch = batch
        ctx.insert(item)
    }

    // MARK: - Round trip

    @Test func roundTrip_PreservesEntityCounts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        let backup = try BackupService.makeBackup(from: ctx)
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: ctx)

        #expect(try ctx.fetch(FetchDescriptor<IngredientCategory>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<Provider>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<StorageLocation>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).count == 2)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<BatchLineItem>()).count == 1)
    }

    @Test func roundTrip_RestoringIntoFreshStore_RebuildsGraph() throws {
        let (sourceContainer, sourceCtx) = try makeContext()
        _ = sourceContainer
        seedFullGraph(sourceCtx)
        let backup = try BackupService.makeBackup(from: sourceCtx)
        let data = try BackupService.encode(backup)

        // Simulate restoring onto another device: a brand-new, empty store.
        let (destContainer, destCtx) = try makeContext()
        _ = destContainer
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: destCtx)

        let ingredient = try #require(try destCtx.fetch(FetchDescriptor<Ingredient>()).first)
        #expect(ingredient.name == "Olive Oil")
        #expect(ingredient.code == "OO1")
        #expect(ingredient.sapValue == 0.1345)
        #expect(ingredient.density == 0.915)
        #expect(ingredient.fattyAcidProfile?.oleic == 69)
        #expect(ingredient.category?.name == "Oils")
        #expect(ingredient.purchases.count == 2)
    }

    @Test func roundTrip_PreservesPurchaseFieldsAndRelationships() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try roundTripInPlace(ctx)

        let purchases = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        let opened = try #require(purchases.first { $0.badge == "LOT1" })
        #expect(opened.remainingAmount == 750)
        #expect(opened.quantity == 1000)
        #expect(opened.provider?.name == "Acme")
        #expect(opened.storageLocation?.name == "Shelf A")
        #expect(opened.ingredient?.name == "Olive Oil")
    }

    @Test func roundTrip_RecipeRelinksIngredientsProductsAndLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try roundTripInPlace(ctx)

        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.superFat == 7)
        #expect(recipe.fragranceUnit == FragranceUnit.percentOfFragrances.rawValue)
        #expect(recipe.lyeIngredient?.name == "Olive Oil")
        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients.first?.ingredient?.name == "Olive Oil")
        #expect(recipe.ingredients.first?.percentage == 100)
        #expect(recipe.products.first?.size == 100)
    }

    @Test func roundTrip_PreservesFavorites() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first).isFavorite = true
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).isFavorite = true
        try ctx.save()

        let backup = try BackupService.makeBackup(from: ctx)
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: ctx)

        #expect(try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first).isFavorite)
        #expect(try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).isFavorite)
    }

    @Test func restore_BackupWithoutFavorites_DefaultsToNotFavorite() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        // A backup written before the field existed simply lacks the key.
        backup.ingredients[0].isFavorite = nil
        backup.recipes[0].isFavorite = nil
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: ctx)

        #expect(try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first).isFavorite == false)
        #expect(try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).isFavorite == false)
    }

    @Test func restore_BackupWithoutFragranceUnit_DefaultsToPercentOfOils() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        // A backup written before the field existed simply lacks the key.
        backup.recipes[0].fragranceUnit = nil
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: ctx)

        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.fragranceUnit == FragranceUnit.percentOfOils.rawValue)
    }

    @Test func roundTrip_BatchLineItemsRelinkToParentsAndPreserveDraws() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let originalPurchaseUUID = seedFullGraph(ctx)
        try roundTripInPlace(ctx)

        let batch = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(batch.recipe?.name == "Castile")
        #expect(batch.lineItems.count == 1)
        let item = try #require(batch.lineItems.first)
        #expect(item.batch === batch)
        #expect(item.ingredient?.name == "Olive Oil")
        #expect(item.draws.first?.amountDrawn == 250)

        // The draw's stable pointer must still resolve to the restored purchase.
        let purchases = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(purchases.contains { $0.uuid == originalPurchaseUUID })
        #expect(item.draws.first?.purchaseUUID == originalPurchaseUUID)
    }

    // MARK: - AppSettings singleton

    @Test func restore_DoesNotDuplicateAppSettings() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try roundTripInPlace(ctx)

        let settings = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.pvpFactor == 4.25)
    }

    // MARK: - Versioning

    @Test func makeBackup_StampsCurrentVersion() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let backup = try BackupService.makeBackup(from: ctx)
        #expect(backup.version == BackupData.currentVersion)
    }

    @Test func decode_NewerVersion_ThrowsUnsupportedVersion() throws {
        let (container, ctx) = try makeContext()
        _ = container
        var backup = try BackupService.makeBackup(from: ctx)
        backup.version = BackupData.currentVersion + 1
        let data = try BackupService.encode(backup)

        #expect(throws: BackupError.self) {
            try BackupService.decode(data)
        }
    }

    @Test func decode_GarbageData_ThrowsMalformedFile() {
        let data = Data("not a backup".utf8)
        #expect(throws: BackupError.self) {
            try BackupService.decode(data)
        }
    }

    @Test func restore_NewerVersion_ThrowsAndLeavesStoreUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.version = BackupData.currentVersion + 1

        #expect(throws: BackupError.self) {
            try BackupService.restore(backup, into: ctx)
        }
        // The destructive wipe must not have run on an unsupported file.
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    // MARK: - Locale independence

    @Test func encode_SerialisesNumbersWithDecimalPoint() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let backup = try BackupService.makeBackup(from: ctx)
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))

        // Numeric values serialise with a dot, never a locale-specific comma.
        #expect(json.contains("4.25"))
        #expect(!json.contains("4,25"))
    }

    @Test func roundTrip_PreservesFractionalDoublesExactly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try roundTripInPlace(ctx)

        let ingredient = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        #expect(ingredient.sapValue == 0.1345)
        #expect(ingredient.density == 0.915)
    }

    // MARK: - Helpers

    /// Export → encode → decode → restore back into the same context.
    private func roundTripInPlace(_ ctx: ModelContext) throws {
        let backup = try BackupService.makeBackup(from: ctx)
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        try BackupService.restore(decoded, into: ctx)
    }
}
