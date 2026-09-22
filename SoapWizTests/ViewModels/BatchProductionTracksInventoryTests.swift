import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Making a batch with inventory tracking off (SW-81): no stock check, no
/// deduction, and a snapshot that records amounts but no cost.
@Suite("BatchProductionViewModel – inventory tracking off", .serialized)
@MainActor
struct BatchProductionTracksInventoryTests: BatchProductionTestHelpers {

    @Test func create_TrackingOff_NoPurchases_Succeeds() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)

        #expect(model.shortages.isEmpty)
        #expect(model.canCreate)
        let batch = try #require(model.create(context: ctx))
        #expect(batch.tracksInventory == false)
        #expect(batch.totalCost == 0)
    }

    @Test func create_TrackingOff_LeavesPurchasesUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let stock = purchase(ctx, for: oil, quantity: 500, totalPrice: 5, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
        _ = try #require(model.create(context: ctx))

        #expect(abs(stock.remainingAmount - 500) < 1e-9)
        #expect(stock.openingDate == nil)
    }

    @Test func create_TrackingOff_RecordsAmountsWithoutDrawsOrCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 2000, totalPrice: 20, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
        model.batchCount = 2
        let batch = try #require(model.create(context: ctx))

        let item = try #require(batch.lineItems.first)
        #expect(batch.lineItems.count == 1)
        #expect(abs(item.amountConsumed - 2000) < 1e-6)
        #expect(item.draws.isEmpty)
        #expect(item.cost == 0)
    }

    @Test func estimatedCost_TrackingOff_IsZeroEvenWithPricedStock() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)

        #expect(model.estimatedCost == 0)
    }

    @Test func create_TrackingOff_NoIngredients_StillCannotCreate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Empty")
        ctx.insert(recipe)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)

        #expect(model.canCreate == false)
        #expect(model.create(context: ctx) == nil)
    }

    @Test func create_TrackingOn_ShortStock_StillBlocks() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let stock = purchase(ctx, for: oil, quantity: 500, totalPrice: 5, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: true)

        #expect(model.shortages.count == 1)
        #expect(model.create(context: ctx) == nil)
        #expect(abs(stock.remainingAmount - 500) < 1e-9)
    }

    @Test func create_TrackingOn_MarksBatchTracked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        #expect(batch.tracksInventory)
        #expect(abs(batch.totalCost - 10) < 1e-9)
    }
}
