import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Lye and neutraliser requirements in `RecipeCoverage`, checked against
/// `BatchProductionViewModel`.
@Suite("Recipe coverage lye", .serialized)
@MainActor
struct RecipeCoverageLyeTests: RecipeCoverageTestHelpers {

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

    // MARK: - Neutraliser

    @Test func coverage_CFMRecipe_RequiresTheNeutralizer() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let setup = neutralizerSetup(ctx, boricStock: 100)

        let result = try #require(try coverage(setup.recipe, ctx, lyes: setup.lyes, neutralizers: [setup.boric]))

        let model = BatchProductionViewModel(
            recipe: setup.recipe,
            lyeCandidates: setup.lyes,
            neutralizerCandidates: [setup.boric]
        )
        #expect(model.requirements.contains { $0.ingredient.name == "Boric Acid" })
        #expect(result.batches >= 1)
        expectAgreement(result, recipe: setup.recipe, lyes: setup.lyes, neutralizers: [setup.boric])
    }

    @Test func coverage_CFMRecipeWithoutNeutralizerCandidate_LeavesItOut() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let setup = neutralizerSetup(ctx, boricStock: 100)

        let result = try #require(try coverage(setup.recipe, ctx, lyes: setup.lyes))

        let model = BatchProductionViewModel(recipe: setup.recipe, lyeCandidates: setup.lyes)
        #expect(!model.requirements.contains { $0.ingredient.name == "Boric Acid" })
        expectAgreement(result, recipe: setup.recipe, lyes: setup.lyes)
    }

    @Test func coverage_CFMNeutralizerShort_ListsItAsTheShortage() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let setup = neutralizerSetup(ctx, boricStock: 5)

        let result = try #require(try coverage(setup.recipe, ctx, lyes: setup.lyes, neutralizers: [setup.boric]))

        #expect(result.batches == 0)
        #expect(result.shortages.map(\.ingredient.name) == ["Boric Acid"])
        expectAgreement(result, recipe: setup.recipe, lyes: setup.lyes, neutralizers: [setup.boric])
    }

    // MARK: - Candidate changes

    @Test func coverage_LyeCandidateAdded_RecomputesAndIncludesTheLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        let calculator = RecipeCoverage()
        let first = try #require(try coverage(recipe, ctx, lyes: [], calculator: calculator))
        #expect(first.shortages.isEmpty)

        let lyes = [lye.naoh]
        let result = try #require(try coverage(recipe, ctx, lyes: lyes, calculator: calculator))

        #expect(calculator.computeCount == 2)
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: lyes)
        #expect(model.requirements.contains { $0.ingredient.name == "Sodium Hydroxide" })
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }

    @Test func coverage_EditedLyeCandidateName_Recomputes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        let lyes = [lye.naoh, lye.koh]
        let calculator = RecipeCoverage()
        _ = try coverage(recipe, ctx, lyes: lyes, calculator: calculator)

        lye.naoh.name = "Caustic Soda"

        let result = try #require(try coverage(recipe, ctx, lyes: lyes, calculator: calculator))
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }

    @Test func coverage_EditedLyeCandidateCategory_RecomputesWithoutThatLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = lyeIngredients(ctx)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        let lyes = [lye.naoh, lye.koh]
        let calculator = RecipeCoverage()
        _ = try coverage(recipe, ctx, lyes: lyes, calculator: calculator)

        let other = IngredientCategory(name: IngredientCategory.Name.additives)
        ctx.insert(other)
        lye.naoh.category = other

        let result = try #require(try coverage(recipe, ctx, lyes: lyes, calculator: calculator))
        #expect(calculator.computeCount == 2)
        expectAgreement(result, recipe: recipe, lyes: lyes)
    }
}
