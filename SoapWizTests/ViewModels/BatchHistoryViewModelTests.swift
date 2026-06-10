import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchHistoryViewModel", .serialized)
@MainActor
struct BatchHistoryViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Batch.self, BatchLineItem.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    private func date(daysAgo: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
    }

    // MARK: - Sort order

    @Test func sortedNewestFirst_EmptyList_ReturnsEmpty() {
        #expect(BatchHistoryViewModel.sortedNewestFirst([]).isEmpty)
    }

    @Test func sortedNewestFirst_MultipleBatches_OrdersByDateDescending() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let old = Batch(recipe: nil, recipeName: "Old", dateCreated: try date(daysAgo: 10), batchCount: 1)
        let newest = Batch(recipe: nil, recipeName: "Newest", dateCreated: try date(daysAgo: 0), batchCount: 1)
        let middle = Batch(recipe: nil, recipeName: "Middle", dateCreated: try date(daysAgo: 5), batchCount: 1)
        for batch in [old, newest, middle] { ctx.insert(batch) }

        let sorted = BatchHistoryViewModel.sortedNewestFirst([old, newest, middle])

        #expect(sorted.map(\.recipeName) == ["Newest", "Middle", "Old"])
    }

    // MARK: - Line item sorting

    @Test func sortedLineItems_NoItems_ReturnsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1)
        ctx.insert(batch)

        #expect(BatchHistoryViewModel.sortedLineItems(of: batch).isEmpty)
    }

    @Test func sortedLineItems_MultipleItems_OrdersAlphabetically() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1)
        ctx.insert(batch)
        for name in ["Olive Oil", "Coconut Oil", "Lye"] {
            let item = BatchLineItem(ingredient: nil, ingredientName: name, amountConsumed: 1, unit: "g", cost: 0, draws: [])
            item.batch = batch
            ctx.insert(item)
        }

        let sorted = BatchHistoryViewModel.sortedLineItems(of: batch)

        #expect(sorted.map(\.ingredientName) == ["Coconut Oil", "Lye", "Olive Oil"])
    }

    // MARK: - Cost per batch

    @Test func costPerBatch_MultipleBatches_DividesTotalCost() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 4, totalCost: 10)

        #expect(abs(BatchHistoryViewModel.costPerBatch(of: batch) - 2.5) < 1e-9)
    }

    @Test func costPerBatch_SingleBatch_EqualsTotalCost() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1, totalCost: 7.25)

        #expect(abs(BatchHistoryViewModel.costPerBatch(of: batch) - 7.25) < 1e-9)
    }

    @Test func costPerBatch_ZeroBatchCount_ReturnsZero() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 0, totalCost: 10)

        #expect(BatchHistoryViewModel.costPerBatch(of: batch) == 0)
    }

    // MARK: - Deleted/edited recipe leaves snapshot intact

    @Test func batchSnapshot_RecipeDeleted_KeepsNameAndLineItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Lavender Soap")
        ctx.insert(recipe)
        let batch = Batch(recipe: recipe, recipeName: "Lavender Soap", batchCount: 2, totalCost: 12)
        ctx.insert(batch)
        let item = BatchLineItem(
            ingredient: nil, ingredientName: "Olive Oil", amountConsumed: 500, unit: "g", cost: 8,
            draws: [BatchPurchaseDraw(purchaseBadge: "L1", amountDrawn: 500, pricePerUnit: 0.016, cost: 8)]
        )
        item.batch = batch
        ctx.insert(item)
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(fetched.recipe == nil)
        #expect(fetched.recipeName == "Lavender Soap")
        #expect(fetched.totalCost == 12)
        let fetchedItem = try #require(fetched.lineItems.first)
        #expect(fetchedItem.ingredientName == "Olive Oil")
        #expect(fetchedItem.amountConsumed == 500)
        let draw = try #require(fetchedItem.draws.first)
        #expect(draw.purchaseBadge == "L1")
        #expect(draw.cost == 8)
    }

    @Test func batchSnapshot_RecipeRenamed_KeepsOriginalName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Lavender Soap")
        ctx.insert(recipe)
        let batch = Batch(recipe: recipe, recipeName: "Lavender Soap", batchCount: 1)
        ctx.insert(batch)
        try ctx.save()

        recipe.name = "Rose Soap"
        try ctx.save()

        #expect(batch.recipeName == "Lavender Soap")
        #expect(batch.recipe?.name == "Rose Soap")
    }
}
