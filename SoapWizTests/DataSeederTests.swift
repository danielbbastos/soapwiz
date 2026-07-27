import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("DataSeeder", .serialized)
@MainActor
struct DataSeederTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            StorageLocation.self, Provider.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Batch.self, BatchLineItem.self
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    @Test func seedDoesNotInsertWhenIngredientsExist() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(Ingredient(name: "Existing"))
        try ctx.save()

        DataSeeder.seedTestIngredients(into: ctx)

        let count = try ctx.fetchCount(FetchDescriptor<Ingredient>())
        #expect(count == 1)
    }

    @Test func seededRecipes_AllPresent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        DataSeeder.seedTestIngredients(into: ctx)
        DataSeeder.seedTestRecipes(into: ctx)

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        let names = Set(recipes.map(\.name))
        #expect(names == ["Classic Bastille Bar", "Everyday Kitchen Bar", "Silky Butter Bar", "Pure Castile"])
    }

    /// Every seeded recipe must be batchable out of the box — that's the point of
    /// the seed data. Guards the JSON stock levels against the recipe definitions.
    @Test func seededRecipes_HaveEnoughStockToCreateOneBatch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        DataSeeder.seedTestIngredients(into: ctx)
        DataSeeder.seedTestRecipes(into: ctx)

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
