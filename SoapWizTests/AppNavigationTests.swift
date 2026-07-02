import Testing
import SwiftUI
import SwiftData
@testable import SoapWiz

@Suite("AppNavigation")
@MainActor
struct AppNavigationTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Batch.self, BatchLineItem.self, Recipe.self, Ingredient.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    private func makeBatch(_ ctx: ModelContext, name: String = "Test Soap") -> Batch {
        let batch = Batch(recipe: nil, recipeName: name, batchCount: 1)
        ctx.insert(batch)
        return batch
    }

    @Test func initialState_InventoryTabAndNoPendingHandoffs() {
        let sut = AppNavigation()

        #expect(sut.selectedTab == .inventory)
        #expect(sut.pendingBatch == nil)
        #expect(sut.pendingRecipeSeed == nil)
    }

    @Test func showBatch_SelectsHistoryTab() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.selectedTab = .recipes

        sut.showBatch(makeBatch(ctx))

        #expect(sut.selectedTab == .history)
    }

    @Test func showBatch_SetsPendingBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        let batch = makeBatch(ctx)

        sut.showBatch(batch)

        #expect(sut.pendingBatch === batch)
    }

    @Test func showBatch_ReplacesPreviousPendingBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.showBatch(makeBatch(ctx, name: "Old Soap"))

        let newBatch = makeBatch(ctx, name: "New Soap")
        sut.showBatch(newBatch)

        #expect(sut.pendingBatch === newBatch)
    }

    @Test func createRecipe_SelectsRecipesTab() {
        let sut = AppNavigation()

        sut.createRecipe(with: [])

        #expect(sut.selectedTab == .recipes)
    }

    @Test func createRecipe_SetsPendingSeedWithIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)

        sut.createRecipe(with: [ingredient])

        let seed = try #require(sut.pendingRecipeSeed)
        #expect(seed.ingredients.count == 1)
        #expect(seed.ingredients.first === ingredient)
    }

    @Test func createRecipe_SameIngredientsTwice_ProducesDistinctSeeds() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)

        sut.createRecipe(with: [ingredient])
        let firstSeed = try #require(sut.pendingRecipeSeed)
        sut.createRecipe(with: [ingredient])
        let secondSeed = try #require(sut.pendingRecipeSeed)

        #expect(firstSeed.id != secondSeed.id)
    }
}
