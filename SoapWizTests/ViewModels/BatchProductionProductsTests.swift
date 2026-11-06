import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The products picked in the create-batch sheet and recorded on the batch (SW-348).
@Suite("BatchProductionViewModel – products", .serialized)
@MainActor
struct BatchProductionProductsTests: BatchProductionTestHelpers {

    private func makeModel(
        _ ctx: ModelContext,
        sizes: [(Double, String)]
    ) -> (BatchProductionViewModel, Recipe) {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 50_000, totalPrice: 50, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        for (size, unit) in sizes {
            let product = RecipeProduct(size: size, unitSymbol: unit)
            product.recipe = recipe
            ctx.insert(product)
        }
        return (BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: true), recipe)
    }

    @Test func productSuggestions_ExcludeWholeBatchAndOnePart() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [
            (1, "whole batch"), (1, "parts of batch"), (4, "parts of batch"), (100, "g")
        ])

        let suggestions = model.productSuggestions

        #expect(suggestions.count == 2)
        #expect(suggestions.map(\.unitSymbol) == ["g", "parts of batch"])
    }

    @Test func suggestions_AreOrderedSmallestMassFirstAndPartsLast() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, recipe) = makeModel(ctx, sizes: [
            (4, "parts of batch"), (1, "lb"), (200, "g"), (0.1, "kg"), (3, "oz")
        ])

        let fromModel = model.productSuggestions
        let shared = BatchProductSuggestion.suggestions(from: recipe.products)

        #expect(fromModel.map(\.id) == shared.map(\.id))
        #expect(fromModel.map(\.unitSymbol) == ["oz", "kg", "g", "lb", "parts of batch"])
    }

    @Test func newRowStart_WithSizes_StartsAtFirstSizeWithItsEstimate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (_, recipe) = makeModel(ctx, sizes: [(200, "g"), (50, "g")])
        let suggestions = BatchProductSuggestion.suggestions(from: recipe.products)

        let start = BatchProductSuggestion.newRowStart(
            from: suggestions, oneBatchWeight: 1000, weightUnit: "g", batchCount: 2
        )

        #expect(start.size == 50)
        #expect(start.unitSymbol == "g")
        #expect(start.count == 40)
    }

    @Test func newRowStart_NoSizes_Starts100gWithItsEstimate() {
        let start = BatchProductSuggestion.newRowStart(
            from: [], oneBatchWeight: 1000, weightUnit: "g", batchCount: 1
        )

        #expect(start.size == 100)
        #expect(start.unitSymbol == "g")
        #expect(start.count == 10)
    }

    @Test func newRowStart_NoWeight_LeavesCountEmpty() {
        let start = BatchProductSuggestion.newRowStart(
            from: [], oneBatchWeight: 0, weightUnit: "", batchCount: 1
        )

        #expect(start.size == 100)
        #expect(start.count == nil)
    }

    @Test func productSuggestions_NoSizes_AreEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [])

        #expect(model.productSuggestions.isEmpty)
    }

    @Test func create_WithPick_RecordsOneProductAtTheEstimate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(100, "g")])
        model.batchCount = 2
        let pick = try #require(model.productSuggestions.first)
        model.selectedProduct = pick.id
        let expected = try #require(model.estimatedCount(for: pick))

        let batch = try #require(model.create(context: ctx))

        let product = try #require(batch.products.first)
        #expect(batch.products.count == 1)
        #expect(product.count == expected)
        #expect(product.size == 100)
        #expect(product.unitSymbol == "g")
        let perBatch = Int((model.totalBatchWeight / 2 / 100 + 1e-9).rounded(.down))
        #expect(expected == 2 * perBatch)
    }

    @Test func estimatedCount_FollowsBatchCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(100, "g")])
        let pick = try #require(model.productSuggestions.first)

        let one = try #require(model.estimatedCount(for: pick))
        model.batchCount = 3

        #expect(model.estimatedCount(for: pick) == 3 * one)
    }

    @Test func create_WithoutPick_RecordsNoProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(100, "g")])

        let batch = try #require(model.create(context: ctx))

        #expect(batch.products.isEmpty)
    }

    @Test func create_PickWithNoEstimate_RecordsNoProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(100, "kg")])
        let pick = try #require(model.productSuggestions.first)
        model.selectedProduct = pick.id

        #expect(model.estimatedCount(for: pick) == nil)
        let batch = try #require(model.create(context: ctx))

        #expect(batch.products.isEmpty)
    }

    @Test func create_PartsPick_RecordsPartsTimesBatchCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(14, "parts of batch")])
        model.batchCount = 2
        model.selectedProduct = try #require(model.productSuggestions.first).id

        let batch = try #require(model.create(context: ctx))

        #expect(batch.products.first?.count == 28)
    }

    @Test func create_StockExactlyEnough_SheetNumbersStayAsTheyWereBeforeCreating() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let stock = purchase(ctx, for: oil, quantity: 1000, totalPrice: 20, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: true)
        let costBefore = model.estimatedCost
        let availableBefore = model.requirements.map(\.available)

        _ = try #require(model.create(context: ctx))

        #expect(stock.remainingAmount < 1e-6)
        #expect(costBefore > 0)
        #expect(model.requirements.map(\.available) == availableBefore)
        #expect(model.shortages.isEmpty)
        #expect(model.canCreate)
        #expect(model.estimatedCost == costBefore)
    }

    @Test func hasChanges_AfterPick_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, _) = makeModel(ctx, sizes: [(100, "g")])
        #expect(model.hasChanges == false)

        model.selectedProduct = try #require(model.productSuggestions.first).id

        #expect(model.hasChanges)
    }

    @Test func products_RecipeEditedOrDeletedAfterwards_StayAsRecorded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let (model, recipe) = makeModel(ctx, sizes: [(100, "g")])
        model.selectedProduct = try #require(model.productSuggestions.first).id
        let batch = try #require(model.create(context: ctx))
        let recorded = batch.products

        for product in recipe.products {
            product.size = 250
        }
        #expect(batch.products == recorded)

        ctx.delete(recipe)
        try ctx.save()

        #expect(batch.products == recorded)
        #expect(batch.recipe == nil)
    }
}
