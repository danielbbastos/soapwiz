import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// `RecipeCoverage` must give the same answer Create Batch gives for the same
/// recipe: every case checks the coverage against `BatchProductionViewModel`
/// at the whole-batch count and one past it.
@Suite("Recipe coverage", .serialized)
@MainActor
struct RecipeCoverageTests: RecipeCoverageTestHelpers {

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

    @Test func coverage_NegativeRemainingStock_ReportsZeroBatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = oil(ctx, stocked: 0)
        let negative = purchase(ctx, for: ingredient, quantity: 100, totalPrice: 5, daysAgo: 3)
        negative.remainingAmount = -50
        let recipe = makeRecipe(ctx, oil: ingredient, oilWeight: 100)

        let result = try #require(try coverage(recipe, ctx))

        #expect(result.batches == 0)
        #expect(result.shortages.map(\.ingredient.name) == ["Olive Oil"])
        expectAgreement(result, recipe: recipe)
    }
}
