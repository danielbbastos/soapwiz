import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchProduction – cost & snapshot", .serialized)
@MainActor
struct BatchProductionCostTests: BatchProductionTestHelpers {

    @Test func create_MultipleIngredients_SumsTotalCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1) // €0.01/g
        let additive = Ingredient(name: "Sodium Lactate", unit: "g")
        ctx.insert(additive)
        purchase(ctx, for: additive, quantity: 200, totalPrice: 4, daysAgo: 1) // €0.02/g

        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        let additiveIngredient = RecipeIngredient(ingredient: additive, percentage: 0, role: .additive)
        additiveIngredient.additiveAmount = 200
        additiveIngredient.additiveUnit = "g"
        additiveIngredient.recipe = recipe
        ctx.insert(additiveIngredient)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        #expect(batch.lineItems.count == 2)
        // Oil: 1000 × 0.01 = 10; Additive: 200 × 0.02 = 4 → 14
        #expect(abs(batch.totalCost - 14) < 1e-6)
        #expect(abs(batch.totalCost - batch.lineItems.reduce(0) { $0 + $1.cost }) < 1e-6)
    }
    @Test func estimatedCost_NoIngredients_ReturnsZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Empty")
        ctx.insert(recipe)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        #expect(model.estimatedCost == 0)
    }
    @Test func estimatedCost_SpansMultiplePurchases_UsesFIFOPrices() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        // Oldest first: 600 g @ €0.01/g, then 600 g @ €0.02/g.
        purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        // 600 × 0.01 + 400 × 0.02 = 6 + 8 = 14
        #expect(abs(model.estimatedCost - 14) < 1e-6)
    }
    @Test func estimatedCost_MatchesCreatedBatchTotalCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let additive = Ingredient(name: "Sodium Lactate", unit: "g")
        ctx.insert(additive)
        purchase(ctx, for: additive, quantity: 200, totalPrice: 4, daysAgo: 1)

        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        let additiveIngredient = RecipeIngredient(ingredient: additive, percentage: 0, role: .additive)
        additiveIngredient.additiveAmount = 200
        additiveIngredient.additiveUnit = "g"
        additiveIngredient.recipe = recipe
        ctx.insert(additiveIngredient)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let estimate = model.estimatedCost
        let batch = try #require(model.create(context: ctx))

        #expect(abs(estimate - batch.totalCost) < 1e-6)
    }
    @Test func estimatedCost_MultipleBatches_ScalesWithCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 2500, totalPrice: 25, daysAgo: 1) // €0.01/g
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        #expect(abs(model.estimatedCost - 10) < 1e-6)

        model.batchCount = 2
        #expect(abs(model.estimatedCost - 20) < 1e-6)
    }
    @Test func estimatedCost_DoesNotMutateInventory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase1 = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        let purchase2 = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        _ = model.estimatedCost
        _ = model.estimatedCost

        #expect(abs(purchase1.remainingAmount - 600) < 1e-6)
        #expect(abs(purchase2.remainingAmount - 600) < 1e-6)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).isEmpty)
    }
    @Test func snapshot_EditingRecipeAfterwards_DoesNotChangeBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))
        let originalCost = batch.totalCost

        // Edit the recipe after the fact.
        recipe.name = "Renamed Recipe"
        recipe.ingredients.forEach { ctx.delete($0) }

        #expect(batch.recipeName == "Test Soap")
        #expect(batch.totalCost == originalCost)
        let item = try #require(batch.lineItems.first)
        #expect(item.ingredientName == "Olive Oil")
        #expect(abs(item.amountConsumed - 1000) < 1e-6)
    }
    @Test func snapshot_DeletingRecipeAfterwards_NullifiesLinkButKeepsSnapshot() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        // A recipe used in a batch can still be deleted — the save must succeed
        // (the soft `.nullify` link drops) and the snapshot stays intact.
        ctx.delete(recipe)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).isEmpty)
        let persisted = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(persisted.recipe == nil)
        #expect(persisted.recipeName == "Test Soap")
        #expect(persisted.lineItems.count == 1)
        let item = try #require(persisted.lineItems.first)
        #expect(item.ingredientName == "Coconut Oil")
    }
    @Test func snapshot_DeletingIngredientAfterwards_NullifiesLinkButKeepsSnapshot() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        try #require(model.create(context: ctx))

        // An ingredient consumed by a batch can still be deleted — the save must
        // succeed (the soft `.nullify` link drops) and the snapshot stays intact.
        recipe.ingredients.forEach { ctx.delete($0) }
        ctx.delete(oil)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).isEmpty)
        let persisted = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        let item = try #require(persisted.lineItems.first)
        #expect(item.ingredient == nil)
        #expect(item.ingredientName == "Olive Oil")
        #expect(abs(item.amountConsumed - 1000) < 1e-6)
    }
}
