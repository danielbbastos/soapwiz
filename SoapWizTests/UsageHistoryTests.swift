import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("UsageHistory", .serialized)
@MainActor
struct UsageHistoryTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Batch.self, BatchLineItem.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    /// A recipe measured directly in grams with a single oil of `oilWeight` g,
    /// no lye ingredient — gives a predictable required amount of `oilWeight`.
    private func makeRecipe(_ ctx: ModelContext, oil: Ingredient, oilWeight: Double) -> Recipe {
        let recipe = Recipe(name: "Test Soap")
        recipe.weightUnit = "g"
        recipe.lyePurity = 100
        recipe.superFat = 0
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: oil, percentage: oilWeight, role: .oil)
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)
        return recipe
    }

    @discardableResult
    private func purchase(
        _ ctx: ModelContext, for ingredient: Ingredient,
        quantity: Double, totalPrice: Double, daysAgo: Int,
        badge: String = "", journalCode: String = ""
    ) -> IngredientPurchase {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let purchase = IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: totalPrice,
            badge: badge, journalCode: journalCode, expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = ingredient
        ctx.insert(purchase)
        return purchase
    }

    @discardableResult
    private func produceBatch(_ ctx: ModelContext, recipe: Recipe, daysAgo: Int = 0) throws -> Batch {
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))
        if daysAgo > 0 {
            batch.dateCreated = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        }
        return batch
    }

    // MARK: - Draw snapshots record purchase identity

    @Test func create_RecordsPurchaseUUIDOnEachDraw() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let batch = try produceBatch(ctx, recipe: recipe)

        let item = try #require(batch.lineItems.first)
        #expect(item.draws.count == 2)
        #expect(item.draws[0].purchaseUUID == older.uuid)
        #expect(item.draws[1].purchaseUUID == newer.uuid)
    }

    // MARK: - Ingredient entries

    @Test func ingredientEntries_NeverUsed_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)

        #expect(UsageHistory.entries(for: oil).isEmpty)
    }

    @Test func ingredientEntries_AfterBatch_BuildsAmountDateAndSources() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10, badge: "OLD")
        purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2, badge: "NEW")
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let batch = try produceBatch(ctx, recipe: recipe)

        let entry = try #require(UsageHistory.entries(for: oil).first)
        #expect(UsageHistory.entries(for: oil).count == 1)
        #expect(entry.batch === batch)
        #expect(entry.date == batch.dateCreated)
        #expect(abs(entry.amount - 1000) < 1e-6)
        #expect(entry.unit == "g")
        #expect(entry.sourceLabels == ["Lot OLD", "Lot NEW"])
    }

    @Test func ingredientEntries_MultipleBatches_SortedNewestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 30)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let olderBatch = try produceBatch(ctx, recipe: recipe, daysAgo: 5)
        let newerBatch = try produceBatch(ctx, recipe: recipe, daysAgo: 1)

        let entries = UsageHistory.entries(for: oil)
        #expect(entries.count == 2)
        #expect(entries[0].batch === newerBatch)
        #expect(entries[1].batch === olderBatch)
    }

    @Test func ingredientEntries_EmptyBadge_FallsBackToJournalCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1, journalCode: "J-42")
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        try produceBatch(ctx, recipe: recipe)

        let entry = try #require(UsageHistory.entries(for: oil).first)
        #expect(entry.sourceLabels == ["Journal J-42"])
    }

    @Test func ingredientEntries_EmptyBadgeAndJournal_ShowsNoLot() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        try produceBatch(ctx, recipe: recipe)

        let entry = try #require(UsageHistory.entries(for: oil).first)
        #expect(entry.sourceLabels == ["No lot"])
    }

    @Test func ingredientEntries_LineItemWithoutBatch_IsSkipped() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let orphan = BatchLineItem(
            ingredient: oil, ingredientName: "Olive Oil",
            amountConsumed: 100, unit: "g", cost: 1, draws: []
        )
        ctx.insert(orphan)

        #expect(UsageHistory.entries(for: oil).isEmpty)
    }

    // MARK: - Purchase entries

    @Test func purchaseEntries_NeverDrawn_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 10)
        let untouched = purchase(ctx, for: oil, quantity: 1000, totalPrice: 10, daysAgo: 1)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        // FIFO drains only the older purchase; the newer one stays untouched.
        try produceBatch(ctx, recipe: recipe)

        #expect(UsageHistory.entries(for: untouched).isEmpty)
    }

    @Test func purchaseEntries_BatchSpanningPurchases_SplitsPerPurchase() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(oil)
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10)
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let batch = try produceBatch(ctx, recipe: recipe)

        let olderEntry = try #require(UsageHistory.entries(for: older).first)
        #expect(UsageHistory.entries(for: older).count == 1)
        #expect(abs(olderEntry.amount - 600) < 1e-6)
        #expect(olderEntry.batch === batch)
        #expect(olderEntry.date == batch.dateCreated)
        #expect(olderEntry.unit == "g")
        #expect(olderEntry.sourceLabels.isEmpty)

        let newerEntry = try #require(UsageHistory.entries(for: newer).first)
        #expect(abs(newerEntry.amount - 400) < 1e-6)
    }

    @Test func purchaseEntries_MultipleBatches_SortedNewestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase = purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 30)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)

        let olderBatch = try produceBatch(ctx, recipe: recipe, daysAgo: 5)
        let newerBatch = try produceBatch(ctx, recipe: recipe, daysAgo: 1)

        let entries = UsageHistory.entries(for: purchase)
        #expect(entries.count == 2)
        #expect(entries[0].batch === newerBatch)
        #expect(entries[1].batch === olderBatch)
        #expect(entries.allSatisfy { abs($0.amount - 1000) < 1e-6 })
    }

    @Test func purchaseEntries_PurchaseWithoutIngredient_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 100, totalPrice: 1,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(purchase)

        #expect(UsageHistory.entries(for: purchase).isEmpty)
    }

    @Test func purchaseEntries_DuplicateBadges_DoNotCrossMatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        // Two purchases with the identical badge — only UUIDs can tell them apart.
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10, badge: "LOT-1")
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2, badge: "LOT-1")
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 600)

        // Drains exactly the older purchase.
        try produceBatch(ctx, recipe: recipe)

        #expect(UsageHistory.entries(for: older).count == 1)
        #expect(UsageHistory.entries(for: newer).isEmpty)
    }
}
