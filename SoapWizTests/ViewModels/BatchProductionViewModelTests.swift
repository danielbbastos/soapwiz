import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchProductionViewModel", .serialized)
@MainActor
struct BatchProductionViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Batch.self, BatchLineItem.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    /// A recipe measured directly in grams with a single oil of `oilWeight` g, no
    /// lye ingredient (so only the oil appears as a requirement) — gives a
    /// predictable required amount of exactly `oilWeight`.
    private func makeRecipe(_ ctx: ModelContext, oil: Ingredient, oilWeight: Double) -> Recipe {
        let recipe = Recipe(name: "Test Soap")
        recipe.weightUnit = "g"
        recipe.lyePurity = 100
        recipe.superFat = 0
        ctx.insert(recipe)
        let ri = RecipeIngredient(ingredient: oil, percentage: oilWeight, role: .oil)
        ri.recipe = recipe
        ctx.insert(ri)
        return recipe
    }

    @discardableResult
    private func purchase(
        _ ctx: ModelContext, for ingredient: Ingredient,
        quantity: Double, totalPrice: Double, daysAgo: Int, badge: String = ""
    ) -> IngredientPurchase {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let p = IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: totalPrice,
            badge: badge, journalCode: "", expiryDate: nil, openingDate: nil
        )
        p.ingredient = ingredient
        ctx.insert(p)
        return p
    }

    // MARK: - Requirements

    @Test func requirements_NoIngredients_IsEmptyAndCannotCreate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Empty")
        ctx.insert(recipe)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        #expect(model.requirements.isEmpty)
        #expect(model.canCreate == false)
        #expect(model.create(context: ctx) == nil)
    }

    @Test func requirements_SingleOil_ConvertsToInventoryUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        let req = try #require(model.requirements.first)
        #expect(model.requirements.count == 1)
        #expect(abs(req.required - 1000) < 1e-6)
        #expect(abs(req.available - 1000) < 1e-6)
        #expect(req.isShort == false)
    }

    // MARK: - FIFO consumption

    @Test func create_FIFO_DrainsOldestPurchaseFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        // Oldest first: 600 g @ €0.01/g, then 600 g @ €0.02/g.
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10, badge: "OLD")
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2, badge: "NEW")
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        // 600 from older (drained), 400 from newer.
        #expect(abs(older.remainingAmount - 0) < 1e-6)
        #expect(abs(newer.remainingAmount - 200) < 1e-6)

        let item = try #require(batch.lineItems.first)
        #expect(item.draws.count == 2)
        #expect(item.draws[0].purchaseBadge == "OLD")
        #expect(item.draws[1].purchaseBadge == "NEW")
        // Cost: 600 × 0.01 + 400 × 0.02 = 6 + 8 = 14
        #expect(abs(item.cost - 14) < 1e-6)
    }

    @Test func create_ExactStock_Succeeds() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let p = purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        #expect(model.shortages.isEmpty)
        let batch = try #require(model.create(context: ctx))

        #expect(abs(p.remainingAmount - 0) < 1e-6)
        #expect(batch.lineItems.count == 1)
    }

    // MARK: - Insufficient stock

    @Test func create_InsufficientStock_BlocksAndMutatesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let p1 = purchase(ctx, for: oil, quantity: 500, totalPrice: 5, daysAgo: 5)
        let p2 = purchase(ctx, for: oil, quantity: 400, totalPrice: 4, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000) // needs 1000, only 900 available

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        let shortage = try #require(model.shortages.first)
        #expect(abs(shortage.shortfall - 100) < 1e-6)
        #expect(model.canCreate == false)
        #expect(model.create(context: ctx) == nil)

        // Nothing deducted.
        #expect(abs(p1.remainingAmount - 500) < 1e-6)
        #expect(abs(p2.remainingAmount - 400) < 1e-6)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty)
        let items = try ctx.fetch(FetchDescriptor<BatchLineItem>())
        #expect(items.isEmpty)
    }

    // MARK: - Multi-batch multiplier

    @Test func create_MultipleBatches_MultipliesRequiredAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let p = purchase(ctx, for: oil, quantity: 2500, totalPrice: 25, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        model.batchCount = 2

        let req = try #require(model.requirements.first)
        #expect(abs(req.required - 2000) < 1e-6)

        let batch = try #require(model.create(context: ctx))
        #expect(batch.batchCount == 2)
        #expect(abs(p.remainingAmount - 500) < 1e-6)
        let item = try #require(batch.lineItems.first)
        #expect(abs(item.amountConsumed - 2000) < 1e-6)
    }

    // MARK: - Volume → mass density deduction

    @Test func create_VolumeInventoryUnit_DeductsViaDensity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        // Oil measured in grams in the recipe, but stocked in mL.
        let oil = Ingredient(name: "Olive Oil", unit: "ml")
        oil.density = 0.8 // g/mL
        ctx.insert(oil)
        let p = purchase(ctx, for: oil, quantity: 1300, totalPrice: 13, daysAgo: 1) // €0.01/mL
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000) // 1000 g

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        // 1000 g ÷ 0.8 g/mL = 1250 mL
        let req = try #require(model.requirements.first)
        #expect(abs(req.required - 1250) < 1e-6)
        #expect(req.unit == "ml")

        let batch = try #require(model.create(context: ctx))
        #expect(abs(p.remainingAmount - 50) < 1e-6)
        let item = try #require(batch.lineItems.first)
        #expect(abs(item.amountConsumed - 1250) < 1e-6)
        // 1250 mL × €0.01/mL = €12.50
        #expect(abs(item.cost - 12.5) < 1e-6)
    }

    @Test func create_VolumeUnit_NoDensity_UsesDefaultDensity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Mystery Oil", unit: "ml") // no density recorded
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 920)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        // Falls back to 0.92 g/mL: 920 g ÷ 0.92 = 1000 mL
        let req = try #require(model.requirements.first)
        #expect(abs(req.required - 1000) < 1e-6)
    }

    // MARK: - Cost totals

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
        let ai = RecipeIngredient(ingredient: additive, percentage: 0, role: .additive)
        ai.additiveAmount = 200
        ai.additiveUnit = "g"
        ai.recipe = recipe
        ctx.insert(ai)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        #expect(batch.lineItems.count == 2)
        // Oil: 1000 × 0.01 = 10; Additive: 200 × 0.02 = 4 → 14
        #expect(abs(batch.totalCost - 14) < 1e-6)
        #expect(abs(batch.totalCost - batch.lineItems.reduce(0) { $0 + $1.cost }) < 1e-6)
    }

    // MARK: - Estimated cost

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
        let ai = RecipeIngredient(ingredient: additive, percentage: 0, role: .additive)
        ai.additiveAmount = 200
        ai.additiveUnit = "g"
        ai.recipe = recipe
        ctx.insert(ai)

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
        let p1 = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        let p2 = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        _ = model.estimatedCost
        _ = model.estimatedCost

        #expect(abs(p1.remainingAmount - 600) < 1e-6)
        #expect(abs(p2.remainingAmount - 600) < 1e-6)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).isEmpty)
    }

    // MARK: - Snapshot immutability

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
