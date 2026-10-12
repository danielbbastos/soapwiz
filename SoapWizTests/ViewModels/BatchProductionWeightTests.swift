import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The total weight and its unit recorded on the batch when it's made (SW-259).
@Suite("BatchProductionViewModel – total weight", .serialized)
@MainActor
struct BatchProductionWeightTests: BatchProductionTestHelpers {

    @Test func create_SingleBatch_StoresSingleBatchWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: true)
        let expected = model.totalBatchWeight
        let batch = try #require(model.create(context: ctx))

        #expect(expected > 0)
        #expect(abs(batch.totalWeight - expected) < 1e-9)
        #expect(batch.totalWeightUnit == "g")
    }

    @Test func create_ThreeBatches_StoresThreeTimesSingleBatchWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: true)
        let single = model.totalBatchWeight
        model.batchCount = 3
        let batch = try #require(model.create(context: ctx))

        #expect(abs(batch.totalWeight - 3 * single) < 1e-9)
        #expect(batch.totalWeightUnit == recipe.weightUnit)
    }

    @Test func create_TrackingOff_StillStoresWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
        let expected = model.totalBatchWeight
        let batch = try #require(model.create(context: ctx))

        #expect(batch.tracksInventory == false)
        #expect(expected > 0)
        #expect(abs(batch.totalWeight - expected) < 1e-9)
        #expect(batch.totalWeightUnit == "g")
    }

    @Test func create_NonGramRecipe_StoresThatUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 32)
        recipe.weightUnit = "oz"

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
        let expected = model.totalBatchWeight
        let batch = try #require(model.create(context: ctx))

        #expect(batch.totalWeightUnit == "oz")
        #expect(abs(batch.totalWeight - expected) < 1e-9)
    }
}
