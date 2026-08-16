import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Ordering and fallbacks are asserted against `topOils` and `soapType` rather
/// than the rendered strings: the composition line formats percentages through
/// the user's locale, and pinning "70%" would pass here and fail on a comma
/// decimal separator.
@MainActor
@Suite
struct RecipeRowSummaryTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Composition

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

    @Test func topOils_ZeroPercentageOil_IsExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100), ("Placeholder", 0)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Olive"])
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

    @Test func composition_NoOilsAndNoDescription_BothAreNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.composition == nil)
        #expect(summary.summaryDescription == nil)
    }

    // MARK: - Soap type

    @Test func soapType_SingleNaOH_IsSolid() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.lyeType = "NaOH"

        #expect(RecipeRowSummary(recipe: recipe).soapType == .solid)
    }

    @Test func soapType_SingleKOH_IsLiquid() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.lyeType = "KOH"

        #expect(RecipeRowSummary(recipe: recipe).soapType == .liquid)
    }

    @Test func soapType_HybridWithMeaningfulNaOH_IsCream() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.useHybrid = true
        recipe.naohPercentage = 30

        #expect(RecipeRowSummary(recipe: recipe).soapType == .cream)
    }

    @Test func soapType_HybridKOHDominant_IsLiquid() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.useHybrid = true
        recipe.naohPercentage = 5

        #expect(RecipeRowSummary(recipe: recipe).soapType == .liquid)
    }

    /// The row must agree with the form and stats rather than reclassify.
    @Test func soapType_MatchesClassifyForTheSameConfiguration() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.useHybrid = true
        recipe.naohPercentage = 12
        recipe.lyeType = "KOH"

        let expected = SoapType.classify(
            useHybrid: recipe.useHybrid,
            naohPercentage: recipe.naohPercentage,
            lyeType: recipe.lyeType
        )

        #expect(RecipeRowSummary(recipe: recipe).soapType == expected)
    }

    // MARK: - Footnote

    @Test func footnote_SingleIngredient_IsSingular() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.addOils([("Olive", 100)], in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).footnote == "1 item")
    }

    @Test func footnote_NoIngredients_IsPlural() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).footnote == "0 items")
    }

    // MARK: - Subtitle

    @Test func subtitle_PercentageMode_UsesTheRecipesOilWeightUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.totalOilWeight = 1000
        recipe.oilWeightUnit = "oz"

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.oilWeight == 1000)
        #expect(summary.displayWeightUnit == "oz")
        // The number's formatting is the locale's business; the unit and the
        // soap-type label are not.
        #expect(summary.subtitle.hasSuffix(" oz"))
        #expect(summary.subtitle.hasPrefix(SoapType.solid.label))
    }

    /// Nothing writes `totalOilWeight` in absolute mode — the form only offers
    /// that field in percentage mode — so a zero must not render as "0 g".
    @Test func subtitle_NoBatchWeight_DropsToTheSoapTypeAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)

        #expect(RecipeRowSummary(recipe: recipe).subtitle == SoapType.solid.label)
    }

    // MARK: - Absolute weight mode

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

    /// The batch size has to be summed from the oils, exactly as `LyeCalculator`
    /// does, because `totalOilWeight` is never written in this mode.
    @Test func subtitle_AbsoluteMode_SumsBatchWeightFromTheOils() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(weightUnit: "g", in: ctx)
        recipe.addOils([("Olive", 700), ("Coconut", 200), ("Castor", 100)], in: ctx)

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.oilWeight == 1000)
        #expect(summary.subtitle.hasSuffix(" g"))
    }

    /// An unresolved line has no name to show, but it still has mass in the pot.
    @Test func subtitle_AbsoluteMode_CountsUnnamedOilsTowardTheBatchWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(weightUnit: "g", in: ctx)
        recipe.addOils([("Olive", 700)], in: ctx)
        let orphan = RecipeIngredient(ingredient: nil, percentage: 300, role: .oil)
        ctx.insert(orphan)
        orphan.recipe = recipe

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.oilWeight == 1000)
        #expect(summary.topOils.map(\.name) == ["Olive"])
    }

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
}

// MARK: - Fixtures

@MainActor
private extension Recipe {
    /// Defaults to percentage mode. `Recipe.weightUnit` itself defaults to "g",
    /// which is absolute mode — so a fixture that does not say puts every oil
    /// amount in grams while the assertion reads it as a percentage. Tests that
    /// want absolute mode pass it explicitly.
    static func mock(
        name: String = "Test Recipe",
        desc: String = "",
        weightUnit: String = "%",
        in ctx: ModelContext
    ) -> Recipe {
        let recipe = Recipe(name: name, desc: desc)
        recipe.weightUnit = weightUnit
        ctx.insert(recipe)
        return recipe
    }

    func addOils(_ oils: [(String, Double)], in ctx: ModelContext) {
        for (name, percentage) in oils {
            addLine(name: name, percentage: percentage, role: .oil, in: ctx)
        }
    }

    func addLine(
        name: String,
        percentage: Double,
        role: RecipeIngredientRole,
        in ctx: ModelContext
    ) {
        let ingredient = Ingredient(name: name, unit: "g")
        ctx.insert(ingredient)
        let line = RecipeIngredient(ingredient: ingredient, percentage: percentage, role: role)
        ctx.insert(line)
        line.recipe = self
    }
}
