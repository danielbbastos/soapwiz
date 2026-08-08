import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchProductionViewModel – consumption", .serialized)
@MainActor
struct BatchProductionViewModelTests: BatchProductionTestHelpers {

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

        // Every purchase the plan draws from is opened, not just the first.
        #expect(older.openingDate != nil)
        #expect(newer.openingDate != nil)

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
        let purchase = purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        #expect(model.shortages.isEmpty)
        let batch = try #require(model.create(context: ctx))

        #expect(abs(purchase.remainingAmount - 0) < 1e-6)
        #expect(batch.lineItems.count == 1)
    }
    @Test func create_InsufficientStock_BlocksAndMutatesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase1 = purchase(ctx, for: oil, quantity: 500, totalPrice: 5, daysAgo: 5)
        let purchase2 = purchase(ctx, for: oil, quantity: 400, totalPrice: 4, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000) // needs 1000, only 900 available

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        let shortage = try #require(model.shortages.first)
        #expect(abs(shortage.shortfall - 100) < 1e-6)
        #expect(model.canCreate == false)
        #expect(model.create(context: ctx) == nil)

        // Nothing deducted.
        #expect(abs(purchase1.remainingAmount - 500) < 1e-6)
        #expect(abs(purchase2.remainingAmount - 400) < 1e-6)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty)
        let items = try ctx.fetch(FetchDescriptor<BatchLineItem>())
        #expect(items.isEmpty)
    }
    @Test func create_MultipleBatches_MultipliesRequiredAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase = purchase(ctx, for: oil, quantity: 2500, totalPrice: 25, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        model.batchCount = 2

        let req = try #require(model.requirements.first)
        #expect(abs(req.required - 2000) < 1e-6)

        let batch = try #require(model.create(context: ctx))
        #expect(batch.batchCount == 2)
        #expect(abs(purchase.remainingAmount - 500) < 1e-6)
        let item = try #require(batch.lineItems.first)
        #expect(abs(item.amountConsumed - 2000) < 1e-6)
    }
    @Test func create_VolumeInventoryUnit_DeductsViaDensity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        // Oil measured in grams in the recipe, but stocked in mL.
        let oil = Ingredient(name: "Olive Oil", unit: "ml")
        oil.density = 0.8 // g/mL
        ctx.insert(oil)
        let purchase = purchase(ctx, for: oil, quantity: 1300, totalPrice: 13, daysAgo: 1) // €0.01/mL
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000) // 1000 g

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        // 1000 g ÷ 0.8 g/mL = 1250 mL
        let req = try #require(model.requirements.first)
        #expect(abs(req.required - 1250) < 1e-6)
        #expect(req.unit == "ml")

        let batch = try #require(model.create(context: ctx))
        #expect(abs(purchase.remainingAmount - 50) < 1e-6)
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
    @Test func create_PurchaseAlreadyOpened_KeepsOriginalDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 2)
        let existingDate = try #require(Calendar.current.date(byAdding: .day, value: -5, to: .now))
        older.openingDate = existingDate
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        _ = try #require(model.create(context: ctx))

        // A hand-recorded opening date is the more accurate one — never overwritten.
        #expect(older.openingDate == existingDate)
        #expect(newer.openingDate != nil)
    }
    @Test func create_PurchaseNotDrawnFrom_StaysUnopened() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        let older = purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 10)
        let newer = purchase(ctx, for: oil, quantity: 500, totalPrice: 5, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        _ = try #require(model.create(context: ctx))

        // FIFO satisfies the whole requirement from the oldest purchase.
        #expect(older.openingDate != nil)
        #expect(newer.openingDate == nil)
        #expect(abs(newer.remainingAmount - 500) < 1e-6)
    }
    @Test func create_RemainingExceedsQuantity_StillMarksOpened() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        let stock = purchase(ctx, for: oil, quantity: 2000, totalPrice: 20, daysAgo: 10)
        // Editing a purchase's quantity down rewrites `quantity` alone, so
        // `remainingAmount` can sit above it. The draw must still open it.
        stock.quantity = 1200
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 200)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        _ = try #require(model.create(context: ctx))

        #expect(abs(stock.remainingAmount - 1800) < 1e-6)
        #expect(stock.remainingAmount > stock.quantity)
        #expect(stock.openingDate != nil)
    }
    @Test func totalBatchWeight_OilsLyeWaterAndFragrance_SumsAll() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        oil.sapValue = 0.2
        ctx.insert(oil)
        let fragrance = Ingredient(name: "Lavender EO", unit: "g")
        ctx.insert(fragrance)
        // 1000 g oils → 200 g lye (sap 0.2, 100% purity, 0% super fat)
        // → 300 g water (1.5 water parts), plus 30 g of fragrance.
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.fragranceUnit = FragranceUnit.grams.rawValue
        let fragranceLine = RecipeIngredient(ingredient: fragrance, percentage: 0, role: .fragrance)
        fragranceLine.additiveAmount = 30
        fragranceLine.additiveUnit = "g"
        fragranceLine.recipe = recipe
        ctx.insert(fragranceLine)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        #expect(abs(model.totalBatchWeight - 1530) < 1e-6)
        #expect(model.batchWeightUnit == "g")
    }
    @Test func totalBatchWeight_MultipleBatches_ScalesWithCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        oil.sapValue = 0.2
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let single = model.totalBatchWeight
        model.batchCount = 3

        #expect(abs(single - 1500) < 1e-6)
        #expect(abs(model.totalBatchWeight - single * 3) < 1e-6)
    }
    @Test func totalBatchWeight_NoOils_IsZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Empty")
        ctx.insert(recipe)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        #expect(model.totalBatchWeight == 0)
    }
}
