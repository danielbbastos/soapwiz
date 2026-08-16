import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Ordering is asserted against `topOils` rather than the rendered string: the
/// composition line formats amounts through the user's locale, and pinning
/// "70%" would pass here and fail on a comma decimal separator.
@MainActor
@Suite
struct RecipeRowSummaryTests: RecipeRowSummaryTestHelpers {

    // MARK: - Oil shares

    @Test func topOils_MoreThanLimit_PicksHighestSharesDescending() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Castor", 10), ("Olive", 70), ("Palm", 5), ("Coconut", 20)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive", "Coconut", "Castor"])
        #expect(summary.topOils.map(\.amount) == [70, 20, 10])
    }

    @Test func topOils_FewerThanLimit_ReturnsOnlyWhatExists() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 80), ("Coconut", 20)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive", "Coconut"])
    }

    @Test func topOils_NoIngredients_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.isEmpty)
        #expect(summary.ingredientCount == 0)
    }

    @Test func topOils_NonOilRoles_AreExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100)], in: ctx)
        recipe.addLine(name: "Lavender EO", percentage: 90, role: .fragrance, in: ctx)
        recipe.addLine(name: "Clay", percentage: 80, role: .additive, in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive"])
        // The count is every line, not just the oils — the footnote counts what
        // the recipe holds, which is what "3 items" means to a reader.
        #expect(summary.ingredientCount == 3)
    }

    /// `RecipeIngredient.ingredient` is optional because a sync race can deliver
    /// the line first. Such a line must not eat one of the three slots.
    @Test func topOils_LineWithMissingIngredient_DoesNotConsumeASlot() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        let orphan = RecipeIngredient(ingredient: nil, percentage: 95, role: .oil)
        ctx.insert(orphan)
        orphan.recipe = recipe
        recipe.addOils([("Olive", 40), ("Coconut", 30), ("Castor", 20), ("Palm", 10)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive", "Coconut", "Castor"])
    }

    @Test func topOils_EqualShares_OrdersByNameSoTheLineIsStable() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 25), ("Coconut", 25), ("Avocado", 25)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Avocado", "Coconut", "Olive"])
    }

    /// Two oils either side of the cap sharing an amount: the name tiebreak is
    /// what decides which one the user actually sees.
    @Test func topOils_TieStraddlingTheCap_ResolvesByName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 50), ("Coconut", 30), ("Zinc", 10), ("Almond", 10)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive", "Coconut", "Almond"])
    }

    @Test func topOils_ZeroPercentageOil_IsExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100), ("Placeholder", 0)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive"])
    }

    @Test func topOils_NegativeAmount_IsExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100), ("Broken", -5)], in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).topOils.map(\.name) == ["Olive"])
    }

    @Test func topOils_BlankIngredientName_IsExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100), ("", 50)], in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).topOils.map(\.name) == ["Olive"])
    }

    // MARK: - Composition and description lines

    /// The two lines are independent: a recipe with both shows both, which is
    /// what distinguishes two recipes built from the same oils.
    @Test func compositionAndDescription_BothPresent_AreBothOffered() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(desc: "A gentle everyday bar", in: ctx)
        recipe.addOils([("Olive", 70)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)
        let composition = try #require(summary.composition)

        #expect(composition.contains("Olive"))
        #expect(summary.summaryDescription == "A gentle everyday bar")
    }

    /// A recipe nobody has added oils to yet still has to read as something.
    @Test func composition_NoIngredients_IsNilButDescriptionCarriesTheRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(desc: "A gentle everyday bar", in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.composition == nil)
        #expect(summary.summaryDescription == "A gentle everyday bar")
    }

    @Test func composition_NoOilsAndNoDescription_BothAreNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.composition == nil)
        #expect(summary.summaryDescription == nil)
    }

    @Test func summaryDescription_BlankDescription_IsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(desc: "   \n ", in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).summaryDescription == nil)
    }

    @Test func summaryDescription_Whitespace_IsTrimmed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(desc: "  A gentle everyday bar\n", in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).summaryDescription == "A gentle everyday bar")
    }

    // MARK: - Weight modes

    @Test func composition_PercentageMode_LabelsAmountsWithAPercentSign() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 70)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)
        let composition = try #require(summary.composition)

        #expect(summary.sharesArePercentages)
        #expect(composition.hasPrefix("Olive "))
        #expect(composition.hasSuffix("%"))
    }

    /// `RecipeIngredient.percentage` holds the entered amount in both modes, so
    /// in absolute mode it is a weight. Reading it as a percentage regardless is
    /// what made a 700 g oil render as "700%".
    @Test func composition_AbsoluteMode_LabelsAmountsAsWeightsNotPercentages() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(weightUnit: "g", in: ctx)
        recipe.addOils([("Olive", 700), ("Coconut", 200)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)
        let composition = try #require(summary.composition)

        #expect(summary.sharesArePercentages == false)
        #expect(summary.displayWeightUnit == "g")
        #expect(composition.contains("Olive"))
        #expect(composition.contains(" g"))
        #expect(!composition.contains("%"))
    }
}
