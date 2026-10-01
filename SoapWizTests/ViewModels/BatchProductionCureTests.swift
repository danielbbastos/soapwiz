import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The cure a new batch is made with (SW-193): suggested from the recipe and
/// the process, the user's own length kept once picked, and nothing at all
/// for a recipe that isn't a solid bar.
@Suite("Batch production – cure", .serialized)
@MainActor
struct BatchProductionCureTests: BatchProductionTestHelpers {

    /// 1 000 g of a single oil with `profile`, stocked, as a NaOH soap recipe.
    private func seed(
        _ ctx: ModelContext,
        profile: FattyAcidProfile,
        kind: RecipeKind = .soap,
        lyeType: String = "NaOH"
    ) -> Recipe {
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = 0.135
        oil.kohSapValue = 0.19
        oil.fattyAcidProfile = profile
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 10)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.recipeKind = kind.rawValue
        recipe.lyeType = lyeType
        return recipe
    }

    private static let typical = FattyAcidProfile.mock(lauric: 20, myristic: 8, palmitic: 15, stearic: 5, oleic: 40)
    private static let olive = FattyAcidProfile.mock(palmitic: 11, stearic: 3, oleic: 75, linoleic: 10)

    @Test func cureDays_SolidBar_DefaultsToTheEstimatesLongerEnd() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical), lyeCandidates: [])

        #expect(model.cureEstimate?.band == .typicalCold)
        #expect(model.cureDays == 42)
    }

    @Test func cureDays_SwitchingToHotProcess_FollowsTheNewEstimate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical), lyeCandidates: [])

        model.process = .hot

        #expect(model.cureDays == 28)
    }

    @Test func cureDays_ChosenByTheUser_SurvivesAProcessChange() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical), lyeCandidates: [])

        model.cureDays = 35
        model.process = .hot

        #expect(model.cureDays == 35)
    }

    @Test func create_SolidBar_StoresCureAndProcess() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.olive), lyeCandidates: [])
        model.process = .hot

        let batch = try #require(model.create(context: ctx))

        #expect(batch.cureDays == 182)
        #expect(SoapProcess.resolve(batch.process) == .hot)
        #expect(CureBand.resolve(batch.cureBand) == .castile)
    }

    /// The band is the recommendation, kept even when the user picks a length
    /// outside it.
    @Test func create_UserCure_StillStoresTheRecommendedBand() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical), lyeCandidates: [])
        model.process = .hot
        model.cureDays = 70

        let batch = try #require(model.create(context: ctx))

        #expect(CureBand.resolve(batch.cureBand) == .typicalHot)
    }

    @Test func create_UserCure_IsWhatTheBatchStores() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical), lyeCandidates: [])
        model.cureDays = 21

        let batch = try #require(model.create(context: ctx))

        #expect(batch.cureDays == 21)
        #expect(SoapProcess.resolve(batch.process) == .cold)
    }

    @Test func create_NonSoapRecipe_HasNoCure() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical, kind: .general), lyeCandidates: [])

        let batch = try #require(model.create(context: ctx))

        #expect(model.cureEstimate == nil)
        #expect(batch.cureDays == 0)
        #expect(batch.process.isEmpty)
        #expect(batch.cureBand.isEmpty)
    }

    /// A value set on a model whose recipe doesn't cure must not leak onto the
    /// batch either.
    @Test func create_LiquidSoap_HasNoCureEvenWhenOneWasSet() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = BatchProductionViewModel(recipe: seed(ctx, profile: Self.typical, lyeType: "KOH"), lyeCandidates: [])
        model.cureDays = 42
        model.process = .hot

        let batch = try #require(model.create(context: ctx))

        #expect(model.cureEstimate == nil)
        #expect(model.cureDays == 0)
        #expect(batch.cureDays == 0)
        #expect(batch.process.isEmpty)
    }
}
