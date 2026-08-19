import Testing
import SwiftData
@testable import SoapWiz

@Suite(.serialized)
struct RecipeStatsTests {

    @Test func stats_NoDrafts_ReportsNoOils() {
        let stats = RecipeStats(oilDrafts: [])
        #expect(stats.hasOils == false)
        #expect(stats.fattyAcidProfile == .zero)
        #expect(stats.ins == 0)
    }

    @Test func stats_DraftWithZeroAmount_IsIgnored() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        var draft = OilIngredientDraft(ingredient: ing)
        draft.amount = 0
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils == false)
    }

    @Test func stats_SingleOil_ReproducesProfile() throws {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        var draft = OilIngredientDraft(ingredient: ing)
        draft.amount = 100
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.fattyAcidProfile.palmitic == 14)
        #expect(stats.fattyAcidProfile.oleic == 69)
        #expect(abs(try #require(stats.totalNaOHSap) - 0.134) < 0.0001)
    }

    @Test func stats_MultipleOils_WeightsByAmount() throws {
        let coconut = Ingredient.mockOil(name: "Coconut", naohSap: 0.190, lauric: 48, myristic: 19)
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        var draft1 = OilIngredientDraft(ingredient: coconut); draft1.amount = 30
        var draft2 = OilIngredientDraft(ingredient: olive); draft2.amount = 70
        let stats = RecipeStats(oilDrafts: [draft1, draft2])
        #expect(abs(stats.fattyAcidProfile.lauric - 48 * 0.3) < 0.001)
        #expect(abs(stats.fattyAcidProfile.palmitic - 14 * 0.7) < 0.001)
        #expect(abs(try #require(stats.totalNaOHSap) - (0.190 * 0.3 + 0.134 * 0.7)) < 0.0001)
    }

    @Test func stats_MultipleOils_WeightsKOHSap() throws {
        let coconut = Ingredient.mockOil(name: "Coconut", naohSap: 0.190, kohSap: 0.266)
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, kohSap: 0.188)
        var draft1 = OilIngredientDraft(ingredient: coconut); draft1.amount = 30
        var draft2 = OilIngredientDraft(ingredient: olive); draft2.amount = 70
        let stats = RecipeStats(oilDrafts: [draft1, draft2])
        #expect(abs(try #require(stats.totalKOHSap) - (0.266 * 0.3 + 0.188 * 0.7)) < 0.0001)
    }

    // MARK: - Non-soap recipes

    /// Two identical blends, one soap and one not. The composition figures must
    /// match exactly: saponification does not change which fatty acids the fats
    /// are made of, it only changes what the numbers are used for.
    @Test func stats_NonSoap_ProfileAndIodineMatchTheSoapBlend() {
        let coconut = Ingredient.mockOil(name: "Coconut", naohSap: 0.190, lauric: 48, myristic: 19)
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        var draft1 = OilIngredientDraft(ingredient: coconut); draft1.amount = 30
        var draft2 = OilIngredientDraft(ingredient: olive); draft2.amount = 70

        let soap = RecipeStats(oilDrafts: [draft1, draft2], makesSoap: true)
        let general = RecipeStats(oilDrafts: [draft1, draft2], makesSoap: false)

        #expect(general.fattyAcidProfile == soap.fattyAcidProfile)
        #expect(general.iodineValue == soap.iodineValue)
        #expect(general.hasOils == soap.hasOils)
    }

    @Test func stats_NonSoap_ReportsNoINSOrSap() {
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, kohSap: 0.188, oleic: 69)
        var draft = OilIngredientDraft(ingredient: olive); draft.amount = 100

        let stats = RecipeStats(oilDrafts: [draft], makesSoap: false)

        #expect(stats.ins == nil)
        #expect(stats.totalNaOHSap == nil)
        #expect(stats.totalKOHSap == nil)
    }

    @Test func stats_NonSoapWithNoOils_StillReportsNoINSOrSap() {
        let stats = RecipeStats(oilDrafts: [], makesSoap: false)

        #expect(stats.ins == nil)
        #expect(stats.totalNaOHSap == nil)
        #expect(stats.totalKOHSap == nil)
        #expect(stats.hasOils == false)
    }

    @Test func stats_NonSoap_StillComputesIodineFromUnsaturation() {
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        var draft = OilIngredientDraft(ingredient: olive); draft.amount = 100

        let stats = RecipeStats(oilDrafts: [draft], makesSoap: false)

        #expect(abs(stats.iodineValue - 69 * 90 / 100) < 0.0001)
    }

    /// A pure beeswax candle: oils are present, but wax esters carry no
    /// triglyceride profile, so there is nothing to break down.
    @Test func hasFattyAcidData_OnlyProfilelessIngredients_IsFalse() {
        let beeswax = Ingredient(name: "Beeswax", unit: "g")
        beeswax.fattyAcidProfile = .zero
        var draft = OilIngredientDraft(ingredient: beeswax); draft.amount = 100

        let stats = RecipeStats(oilDrafts: [draft], makesSoap: false)

        #expect(stats.hasOils)
        #expect(stats.hasFattyAcidData == false)
    }

    @Test func hasFattyAcidData_IngredientWithNoProfileAtAll_IsFalse() {
        let unknown = Ingredient(name: "Unknown", unit: "g")
        var draft = OilIngredientDraft(ingredient: unknown); draft.amount = 100

        #expect(RecipeStats(oilDrafts: [draft]).hasFattyAcidData == false)
    }

    @Test func hasFattyAcidData_BlendWithOneProfiledOil_IsTrue() {
        let beeswax = Ingredient(name: "Beeswax", unit: "g")
        beeswax.fattyAcidProfile = .zero
        let shea = Ingredient.mockOil(name: "Shea", naohSap: 0.128, stearic: 38, oleic: 50)
        var wax = OilIngredientDraft(ingredient: beeswax); wax.amount = 50
        var butter = OilIngredientDraft(ingredient: shea); butter.amount = 50

        let stats = RecipeStats(oilDrafts: [wax, butter], makesSoap: false)

        #expect(stats.hasFattyAcidData)
        #expect(abs(stats.fattyAcidProfile.stearic - 38 * 0.5) < 0.001)
    }

    @Test func hasFattyAcidData_NoOilsAtAll_IsFalse() {
        #expect(RecipeStats(oilDrafts: []).hasFattyAcidData == false)
    }

    /// A soap recipe whose oils carry no profile must still say so rather than
    /// dropping the section — the state is diagnosable only if it is visible.
    @Test func hasOilsButNoProfile_IsDistinguishableFromHavingNoOils() {
        let unknown = Ingredient(name: "Unknown", unit: "g")
        var draft = OilIngredientDraft(ingredient: unknown); draft.amount = 100

        let withOils = RecipeStats(oilDrafts: [draft])
        let empty = RecipeStats(oilDrafts: [])

        #expect(withOils.hasOils)
        #expect(withOils.hasFattyAcidData == false)
        #expect(empty.hasOils == false)
        #expect(empty.hasFattyAcidData == false)
    }

    @Test func stats_MakesSoapDefaultsToTrue() {
        #expect(RecipeStats(oilDrafts: []).makesSoap)
    }

    @Test func stats_OilWithoutProfile_ContributesZero() {
        let unknown = Ingredient(name: "Unknown", unit: "g")
        var draft = OilIngredientDraft(ingredient: unknown); draft.amount = 100
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils)
        #expect(stats.fattyAcidProfile == .zero)
    }
}

extension Ingredient {
    static func mockOil(
        name: String,
        naohSap: Double,
        kohSap: Double? = nil,
        lauric: Double = 0, myristic: Double = 0,
        palmitic: Double = 0, stearic: Double = 0,
        oleic: Double = 0, linoleic: Double = 0,
        linolenic: Double = 0, ricinoleic: Double = 0
    ) -> Ingredient {
        let ing = Ingredient(name: name, unit: "g")
        ing.sapValue = naohSap
        ing.kohSapValue = kohSap
        var profile = FattyAcidProfile()
        profile.lauric = lauric
        profile.myristic = myristic
        profile.palmitic = palmitic
        profile.stearic = stearic
        profile.oleic = oleic
        profile.linoleic = linoleic
        profile.linolenic = linolenic
        profile.ricinoleic = ricinoleic
        ing.fattyAcidProfile = profile
        return ing
    }
}
