import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("DataSeeder", .serialized)
@MainActor
struct DataSeederTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// The order a debug launch runs them in: the library first, then the
    /// fixtures that stock it.
    private func seedAll(_ ctx: ModelContext) throws {
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        DataSeeder.seedTestIngredients(into: ctx)
        DataSeeder.seedTestRecipes(into: ctx)
    }

    @Test func seedTestIngredients_PurchasesAlreadyExist_DoesNotSeedAgain() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        let ingredient = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 100,
            totalPrice: 1,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ingredient.purchases.append(purchase)
        ctx.insert(purchase)
        try ctx.save()

        DataSeeder.seedTestIngredients(into: ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<IngredientPurchase>()) == 1)
    }

    @Test func seedTestIngredients_StocksLibraryRows_WithoutAddingIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        let before = try ctx.fetchCount(FetchDescriptor<Ingredient>())

        DataSeeder.seedTestIngredients(into: ctx)

        let purchases = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(try ctx.fetchCount(FetchDescriptor<Ingredient>()) == before)
        #expect(!purchases.isEmpty)
        #expect(purchases.allSatisfy { !($0.ingredient?.librarySlug.isEmpty ?? true) })
    }

    @Test func seedAll_LeavesNoDuplicateIngredientNames() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try seedAll(ctx)

        let names = try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name.lookupKey)
        #expect(names.count == Set(names).count)
    }

    @Test func seededRecipes_AllPresent() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try seedAll(ctx)

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        let names = Set(recipes.map(\.name))
        #expect(names == ["Classic Bastille Bar", "Everyday Kitchen Bar", "Silky Butter Bar", "Pure Castile", "Woodland Meadow Bar"])
    }

    /// Every seeded recipe must be batchable out of the box — that's the point of
    /// the seed data. Guards the JSON stock levels against the recipe definitions.
    @Test func seededRecipes_HaveEnoughStockToCreateOneBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try seedAll(ctx)

        let lyesName = IngredientCategory.Name.lyes
        let lyePredicate = #Predicate<Ingredient> { $0.category?.name == lyesName }
        let lyeCandidates = try ctx.fetch(FetchDescriptor(predicate: lyePredicate))
        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(!recipes.isEmpty)

        for recipe in recipes {
            let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: lyeCandidates)
            let shortages = model.shortages
            let detail = shortages
                .map { "\($0.ingredient.name) (need \($0.required), have \($0.available))" }
                .joined(separator: ", ")
            #expect(shortages.isEmpty, "\(recipe.name) is short on: \(detail)")
            #expect(model.canCreate, "\(recipe.name) cannot create a batch")
        }
    }
}
