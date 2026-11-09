import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What `RecipeCoverage` caches, when it recomputes, and what it drops.
@Suite("Recipe coverage cache", .serialized)
@MainActor
struct RecipeCoverageCacheTests: RecipeCoverageTestHelpers {

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

    @Test func prune_DropsRecipesNotKept_OnlyThoseRecompute() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)
        let second = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)
        let calculator = RecipeCoverage()
        _ = try coverage(first, ctx, calculator: calculator)
        _ = try coverage(second, ctx, calculator: calculator)
        #expect(calculator.computeCount == 2)

        calculator.prune(keeping: [first])
        _ = try coverage(first, ctx, calculator: calculator)
        #expect(calculator.computeCount == 2)

        _ = try coverage(second, ctx, calculator: calculator)
        #expect(calculator.computeCount == 3)
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

    @Test func coverage_DeletedIngredientOnALine_KeepsTheRestAndRecomputes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 3000), oilWeight: 1000)
        let butter = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(butter)
        purchase(ctx, for: butter, quantity: 450, totalPrice: 5, daysAgo: 2)
        let line = RecipeIngredient(ingredient: butter, percentage: 0, role: .additive)
        line.additiveAmount = 100
        line.additiveUnit = "g"
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()
        let calculator = RecipeCoverage()
        #expect(try coverage(recipe, ctx, calculator: calculator)?.batches == 3)

        ctx.delete(butter)
        try ctx.save()

        let result = try #require(try coverage(recipe, ctx, calculator: calculator))
        #expect(calculator.computeCount == 2)
        #expect(result.batches == 3)
        #expect(result.shortages.isEmpty)
        expectAgreement(result, recipe: recipe)
    }
}
