import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which recipes Home's "You can make" card offers, in what order, and how it
/// words each row (SW-364).
@Suite("You can make", .serialized)
@MainActor
struct YouCanMakeTests: BatchProductionTestHelpers {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    private func makeModel() -> YouCanMakeModel {
        YouCanMakeModel(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    /// A recipe needing `weight` g of its own oil, with `stocked` g in stock,
    /// so it covers floor(stocked / weight) batches.
    @discardableResult
    private func addRecipe(
        _ ctx: ModelContext,
        name: String,
        weight: Double = 1000,
        stocked: Double
    ) -> Recipe {
        let oil = Ingredient(name: "\(name) Oil", unit: "g")
        oil.sapValue = 0.2
        ctx.insert(oil)
        if stocked > 0 {
            purchase(ctx, for: oil, quantity: stocked, totalPrice: 10, daysAgo: 5)
        }
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: weight)
        recipe.name = name
        return recipe
    }

    private func addBatch(_ ctx: ModelContext, of recipe: Recipe?, on day: Date) {
        ctx.insert(Batch(recipe: recipe, recipeName: recipe?.name ?? "Gone", dateCreated: day, batchCount: 1))
    }

    private func rows(
        _ model: YouCanMakeModel,
        _ ctx: ModelContext,
        tracksInventory: Bool = true
    ) throws -> [MakeableRecipeRow] {
        model.rows(
            recipes: try ctx.fetch(FetchDescriptor<Recipe>()),
            ingredients: try ctx.fetch(FetchDescriptor<Ingredient>()),
            purchases: try ctx.fetch(FetchDescriptor<IngredientPurchase>()),
            batches: try ctx.fetch(FetchDescriptor<Batch>()),
            tracksInventory: tracksInventory,
            now: date(2026, 11, 9)
        )
    }

    // MARK: - Order

    @Test func rows_CoveredRecipes_OrderedByBatchesDescending() throws {
        let (container, ctx) = try makeContext()
        _ = container
        addRecipe(ctx, name: "Two", stocked: 2000)
        addRecipe(ctx, name: "Four", stocked: 4000)
        addRecipe(ctx, name: "Three", stocked: 3000)

        let result = try rows(makeModel(), ctx)

        #expect(result.map(\.recipe.name) == ["Four", "Three", "Two"])
        #expect(result.map(\.batchesText) == ["×4", "×3", "×2"])
    }

    @Test func rows_TiedBatches_MostRecentlyMadeFirstThenNeverMadeThenName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let apple = addRecipe(ctx, name: "Apple", stocked: 2000)
        let bay = addRecipe(ctx, name: "Bay", stocked: 2000)
        addRecipe(ctx, name: "Cedar", stocked: 2000)
        addRecipe(ctx, name: "Aloe", stocked: 2000)
        addBatch(ctx, of: apple, on: date(2026, 1, 5))
        addBatch(ctx, of: bay, on: date(2026, 3, 5))

        let result = try rows(makeModel(), ctx)

        #expect(result.map(\.recipe.name) == ["Bay", "Apple", "Aloe", "Cedar"])
    }

    @Test func rows_ShortRecipes_AfterCoveredFewestShortagesFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let twoShortages = addRecipe(ctx, name: "Needy", stocked: 0)
        let extra = Ingredient(name: "Zinc Oil", unit: "g")
        ctx.insert(extra)
        let line = RecipeIngredient(ingredient: extra, percentage: 500, role: .oil)
        line.recipe = twoShortages
        ctx.insert(line)
        addRecipe(ctx, name: "Almost", stocked: 600)
        addRecipe(ctx, name: "Ready", stocked: 1000)

        let result = try rows(makeModel(), ctx)

        #expect(result.map(\.recipe.name) == ["Ready", "Almost", "Needy"])
        #expect(result.map(\.isShort) == [false, true, true])
    }

    // MARK: - Cap

    @Test func rows_MoreThanFourRecipes_CapsAtFour() throws {
        let (container, ctx) = try makeContext()
        _ = container
        for index in 0..<6 {
            addRecipe(ctx, name: "Recipe \(index)", stocked: 1000)
        }

        let result = try rows(makeModel(), ctx)

        #expect(result.count == YouCanMakeModel.maxRows)
        #expect(YouCanMakeModel.maxRows == 4)
    }

    @Test func rows_CoveredFillTheCap_ShortRecipesDropOut() throws {
        let (container, ctx) = try makeContext()
        _ = container
        for index in 0..<3 {
            addRecipe(ctx, name: "Covered \(index)", stocked: 1000)
        }
        addRecipe(ctx, name: "Short A", stocked: 0)
        addRecipe(ctx, name: "Short B", stocked: 0)

        let result = try rows(makeModel(), ctx)

        #expect(result.count == 4)
        #expect(result.filter(\.isShort).count == 1)
        #expect(result.last?.isShort == true)
    }

    // MARK: - Short text

    @Test func shortText_OneShortage_NamesIngredientAndAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        addRecipe(ctx, name: "Castile", stocked: 360)

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Short on Castile Oil, 640 g")
    }

    @Test func shortText_FractionalShortfall_KeepsTwoDecimalsAtMost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        addRecipe(ctx, name: "Castile", weight: 100, stocked: 87.5)

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Short on Castile Oil, \(BatchAmountFormat.amount(12.5, unit: "g"))")
    }

    @Test func shortText_SeveralShortages_FirstByNameAndCountOfOthers() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Needy", stocked: 0)
        for name in ["Aloe Oil", "Zinc Oil"] {
            let extra = Ingredient(name: name, unit: "g")
            ctx.insert(extra)
            let line = RecipeIngredient(ingredient: extra, percentage: 500, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Short on Aloe Oil, 500 g and 2 more")
    }

    // MARK: - Made text

    @Test func madeText_NeverMade_HasNoSecondLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        addRecipe(ctx, name: "Fresh", stocked: 1000)

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == nil)
    }

    @Test func madeText_Once_SaysOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Fresh", stocked: 1000)
        addBatch(ctx, of: recipe, on: date(2026, 10, 15))

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Made once · last Oct 15")
    }

    @Test func madeText_Twice_SaysTwice() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Fresh", stocked: 1000)
        addBatch(ctx, of: recipe, on: date(2026, 9, 1))
        addBatch(ctx, of: recipe, on: date(2026, 10, 15))

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Made twice · last Oct 15")
    }

    @Test func madeText_ManyBatches_CountsThemAndUsesNewestDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Fresh", stocked: 1000)
        addBatch(ctx, of: recipe, on: date(2026, 10, 15))
        addBatch(ctx, of: recipe, on: date(2026, 2, 1))
        addBatch(ctx, of: recipe, on: date(2026, 5, 20))
        addBatch(ctx, of: recipe, on: date(2026, 1, 3))

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Made 4 times · last Oct 15")
    }

    @Test func madeText_LastBatchInAnotherYear_ShowsTheYear() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Fresh", stocked: 1000)
        addBatch(ctx, of: recipe, on: date(2025, 10, 15))

        let row = try #require(try rows(makeModel(), ctx).first)

        #expect(row.detail == "Made once · last Oct 15, 2025")
    }

    @Test func madeText_OtherRecipesAndRecipelessBatches_AreNotCounted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = addRecipe(ctx, name: "Fresh", stocked: 1000)
        let other = addRecipe(ctx, name: "Other", stocked: 0)
        addBatch(ctx, of: recipe, on: date(2026, 10, 15))
        addBatch(ctx, of: other, on: date(2026, 10, 20))
        addBatch(ctx, of: nil, on: date(2026, 10, 25))

        let row = try #require(try rows(makeModel(), ctx).first { $0.recipe.name == "Fresh" })

        #expect(row.detail == "Made once · last Oct 15")
    }

    // MARK: - Hidden

    @Test func rows_TrackingOff_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        addRecipe(ctx, name: "Fresh", stocked: 1000)

        #expect(try rows(makeModel(), ctx, tracksInventory: false).isEmpty)
    }

    @Test func rows_NoRecipes_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container

        #expect(try rows(makeModel(), ctx).isEmpty)
    }

    @Test func rows_RecipeWithoutRequirements_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(Recipe(name: "Empty"))

        #expect(try rows(makeModel(), ctx).isEmpty)
    }
}
