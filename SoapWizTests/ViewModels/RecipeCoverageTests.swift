import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// `RecipeCoverage` must give the same answer Create Batch gives for the same
/// recipe: every case checks the coverage against `BatchProductionViewModel`
/// at the whole-batch count and one past it.
@Suite("Recipe coverage", .serialized)
@MainActor
struct RecipeCoverageTests: BatchProductionTestHelpers {

    private func stock(_ ctx: ModelContext) throws -> StockLevels {
        StockLevels(try ctx.fetch(FetchDescriptor<IngredientPurchase>()))
    }

    private func coverage(
        _ recipe: Recipe,
        _ ctx: ModelContext,
        lyes: [Ingredient] = [],
        calculator: RecipeCoverage? = nil
    ) throws -> RecipeCoverage.Coverage? {
        (calculator ?? RecipeCoverage()).coverage(
            for: recipe,
            stock: try stock(ctx),
            lyeCandidates: lyes,
            neutralizerCandidates: [],
            tracksInventory: true
        )
    }

    /// Asserts `result` is what Create Batch says: no shortage at its own
    /// count, one at the next, and the same shortfalls for a single batch.
    private func expectAgreement(
        _ result: RecipeCoverage.Coverage,
        recipe: Recipe,
        lyes: [Ingredient] = []
    ) {
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: lyes, tracksInventory: true)
        if result.batches > 0 {
            model.batchCount = result.batches
            #expect(model.shortages.isEmpty)
        }
        model.batchCount = result.batches + 1
        #expect(!model.shortages.isEmpty)

        model.batchCount = 1
        let expected = model.shortages
        #expect(result.shortages.map(\.id) == expected.map(\.id))
        for (shortage, requirement) in zip(result.shortages, expected) {
            #expect(abs(shortage.shortfall - requirement.shortfall) < 1e-9)
            #expect(shortage.unit == requirement.unit)
        }
    }

    private func lyeIngredients(_ ctx: ModelContext) -> (naoh: Ingredient, koh: Ingredient) {
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide", category: lyes, unit: "g")
        let koh = Ingredient(name: "Potassium Hydroxide", category: lyes, unit: "g")
        ctx.insert(naoh)
        ctx.insert(koh)
        purchase(ctx, for: naoh, quantity: 1000, totalPrice: 10, daysAgo: 5)
        purchase(ctx, for: koh, quantity: 1000, totalPrice: 10, daysAgo: 5)
        return (naoh, koh)
    }

    private func oil(_ ctx: ModelContext, unit: String = "g", stocked: Double) -> Ingredient {
        let oil = Ingredient(name: "Olive Oil", unit: unit)
        oil.sapValue = 0.2
        oil.kohSapValue = 0.28
        ctx.insert(oil)
        if stocked > 0 {
            purchase(ctx, for: oil, quantity: stocked, totalPrice: 10, daysAgo: 5)
        }
        return oil
    }

    // MARK: - Whole batches

    @Test func coverage_StockCoversSeveralBatches_CountsWholeBatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3500), oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 3)
        #expect(result.shortages.isEmpty)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_StockIsExactMultiple_CountsAllOfThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 3)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_StockShortOfOneBatch_ReportsZeroAndShortfall() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 600), oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 0)
        let shortage = try #require(result.shortages.first)
        #expect(shortage.ingredient.name == "Olive Oil")
        #expect(abs(shortage.shortfall - 400) < 1e-6)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_IngredientNeverPurchased_IsShortByTheFullAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 0), oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 0)
        #expect(abs(try #require(result.shortages.first).shortfall - 1000) < 1e-6)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_LimitedByTheScarcestIngredient() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 5000), oilWeight: 1000)
        let butter = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(butter)
        purchase(ctx, for: butter, quantity: 450, totalPrice: 5, daysAgo: 2)
        let line = RecipeIngredient(ingredient: butter, percentage: 0, role: .additive)
        line.additiveAmount = 100
        line.additiveUnit = "g"
        line.recipe = recipe
        ctx.insert(line)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 4)
        expectAgreement(result, recipe: recipe)
    }

    // MARK: - Units

    @Test func coverage_VolumeStockWithDensity_ConvertsTheRecipeAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, unit: "ml", stocked: 3000)
        ingredient.density = 0.8
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx))

        // 1000 g ÷ 0.8 g/mL = 1250 mL a batch.
        #expect(result.batches == 2)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_RecipeInOuncesStockInGrams_Converts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 2000), oilWeight: 32)
        recipe.weightUnit = "oz"

        let result = try #require(try coverage(recipe, ctx))

        // 32 oz is about 907 g.
        #expect(result.batches == 2)
        expectAgreement(result, recipe: recipe)
    }

    // MARK: - Lye

    @Test func coverage_NaOHRecipe_RequiresTheLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 5000), oilWeight: 1000)

        let result = try #require(try coverage(recipe, ctx, lyes: [lye.naoh, lye.koh]))

        // 1000 g × 0.2 = 200 g of NaOH a batch, 1000 g in stock.
        #expect(result.batches == 5)
        expectAgreement(result, recipe: recipe, lyes: [lye.naoh, lye.koh])
    }

    @Test func coverage_KOHRecipe_RequiresPotassiumHydroxide() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        recipe.lyeType = "KOH"
        let lyes = [lye.naoh, lye.koh]

        let result = try #require(try coverage(recipe, ctx, lyes: lyes))

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: lyes)
        #expect(model.requirements.contains { $0.ingredient.name == "Potassium Hydroxide" })
        #expect(!model.requirements.contains { $0.ingredient.name == "Sodium Hydroxide" })
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }

    @Test func coverage_HybridRecipe_RequiresBothLyes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        recipe.useHybrid = true
        let lyes = [lye.naoh, lye.koh]

        let result = try #require(try coverage(recipe, ctx, lyes: lyes))

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: lyes)
        let names = model.requirements.map(\.ingredient.name)
        #expect(names.contains("Potassium Hydroxide") && names.contains("Sodium Hydroxide"))
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }

    @Test func coverage_HybridRecipeWithOneLyeShort_ListsOnlyThatLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        recipe.useHybrid = true
        for purchase in lye.koh.purchases { purchase.remainingAmount = 1 }
        let lyes = [lye.naoh, lye.koh]

        let result = try #require(try coverage(recipe, ctx, lyes: lyes))

        #expect(result.batches == 0)
        #expect(result.shortages.map(\.ingredient.name) == ["Potassium Hydroxide"])
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }

    // MARK: - Roles

    @Test func coverage_IngredientInTwoRoles_SumsTheAmounts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let shared = oil(ctx, stocked: 3300)
        let recipe = makeRecipe(ctx, oil: shared, oilWeight: 1000)
        let line = RecipeIngredient(ingredient: shared, percentage: 0, role: .additive)
        line.additiveAmount = 100
        line.additiveUnit = "g"
        line.recipe = recipe
        ctx.insert(line)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 3)
        expectAgreement(result, recipe: recipe)
    }

    // MARK: - Nil cases

    @Test func coverage_InventoryNotTracked_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)

        let result = RecipeCoverage().coverage(
            for: recipe,
            stock: try stock(ctx),
            lyeCandidates: [],
            neutralizerCandidates: [],
            tracksInventory: false
        )

        #expect(result == nil)
    }

    @Test func coverage_RecipeWithNoRequirements_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Empty")
        ctx.insert(recipe)

        #expect(try coverage(recipe, ctx) == nil)
    }

    // MARK: - Stock source

    @Test func coverage_UsesTheStockLevelsItIsGiven() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, stocked: 0)
        let first = purchase(ctx, for: ingredient, quantity: 1500, totalPrice: 10, daysAgo: 5)
        purchase(ctx, for: ingredient, quantity: 1500, totalPrice: 10, daysAgo: 4)
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 1000)

        let subset = StockLevels([first])
        let result = try #require(RecipeCoverage().coverage(
            for: recipe,
            stock: subset,
            lyeCandidates: [],
            neutralizerCandidates: [],
            tracksInventory: true
        ))

        #expect(ingredient.totalRemaining == 3000)
        #expect(result.batches == 1)
    }

    // MARK: - Cache

    @Test func coverage_UnchangedRecipe_IsNotRecomputed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)
        let calculator = RecipeCoverage()

        _ = try coverage(recipe, ctx, calculator: calculator)
        _ = try coverage(recipe, ctx, calculator: calculator)

        #expect(calculator.computeCount == 1)
    }

    @Test func coverage_StockChange_UsesTheCachedRequirementsButNewStock() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, stocked: 3000)
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 1000)
        let calculator = RecipeCoverage()
        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 3)

        purchase(ctx, for: ingredient, quantity: 1000, totalPrice: 5, daysAgo: 1)

        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 4)
        #expect(calculator.computeCount == 1)
    }

    @Test func coverage_EditedRecipeLine_RecomputesWithTheNewAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)
        let calculator = RecipeCoverage()
        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 3)

        try #require(recipe.ingredients.first).percentage = 500

        let result = try #require(try coverage(recipe, ctx, calculator: calculator))
        #expect(result.batches == 6)
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_EditedIngredientDensity_Recomputes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, unit: "ml", stocked: 3000)
        ingredient.density = 0.8
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 1000)
        let calculator = RecipeCoverage()
        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 2)

        ingredient.density = 1.0

        let result = try #require(try coverage(recipe, ctx, calculator: calculator))
        #expect(result.batches == 3)
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_EditedIngredientUnit_Recomputes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, unit: "g", stocked: 3000)
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 1000)
        let calculator = RecipeCoverage()
        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 3)

        ingredient.unit = "kg"

        let result = try #require(try coverage(recipe, ctx, calculator: calculator))
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe)
    }

    @Test func coverage_EditedRecipeSetting_Recomputes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        let lyes = [lye.naoh, lye.koh]
        let calculator = RecipeCoverage()
        _ = try coverage(recipe, ctx, lyes: lyes, calculator: calculator)

        recipe.lyeType = "KOH"

        let result = try #require(try coverage(recipe, ctx, lyes: lyes, calculator: calculator))
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }
}
