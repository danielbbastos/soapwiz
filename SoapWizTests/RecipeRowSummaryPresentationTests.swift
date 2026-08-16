import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The subtitle, soap type and footnote — everything the row states about the
/// recipe as a whole rather than about its oils.
@MainActor
@Suite
struct RecipeRowSummaryPresentationTests: RecipeRowSummaryTestHelpers {

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
}
