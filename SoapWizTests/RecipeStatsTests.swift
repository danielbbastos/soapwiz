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
        draft.amount = "0"
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils == false)
    }

    @Test func stats_DraftWithInvalidAmount_IsIgnored() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        var draft = OilIngredientDraft(ingredient: ing)
        draft.amount = "abc"
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils == false)
    }

    @Test func stats_HandlesCommaDecimalSeparator() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        var draft = OilIngredientDraft(ingredient: ing)
        draft.amount = "50,5"
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils)
        #expect(stats.fattyAcidProfile.oleic == 69)
    }

    @Test func stats_SingleOil_ReproducesProfile() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        var draft = OilIngredientDraft(ingredient: ing)
        draft.amount = "100"
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.fattyAcidProfile.palmitic == 14)
        #expect(stats.fattyAcidProfile.oleic == 69)
        #expect(abs(stats.totalNaOHSap - 0.134) < 0.0001)
    }

    @Test func stats_MultipleOils_WeightsByAmount() {
        let coconut = Ingredient.mockOil(name: "Coconut", naohSap: 0.190, lauric: 48, myristic: 19)
        let olive = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        var d1 = OilIngredientDraft(ingredient: coconut); d1.amount = "30"
        var d2 = OilIngredientDraft(ingredient: olive); d2.amount = "70"
        let stats = RecipeStats(oilDrafts: [d1, d2])
        #expect(abs(stats.fattyAcidProfile.lauric - 48 * 0.3) < 0.001)
        #expect(abs(stats.fattyAcidProfile.palmitic - 14 * 0.7) < 0.001)
        #expect(abs(stats.totalNaOHSap - (0.190 * 0.3 + 0.134 * 0.7)) < 0.0001)
    }

    @Test func stats_OilWithoutProfile_ContributesZero() {
        let unknown = Ingredient(name: "Unknown", unit: "g")
        var draft = OilIngredientDraft(ingredient: unknown); draft.amount = "100"
        let stats = RecipeStats(oilDrafts: [draft])
        #expect(stats.hasOils)
        #expect(stats.fattyAcidProfile == .zero)
    }
}

extension Ingredient {
    static func mockOil(
        name: String,
        naohSap: Double,
        lauric: Double = 0, myristic: Double = 0,
        palmitic: Double = 0, stearic: Double = 0,
        oleic: Double = 0, linoleic: Double = 0,
        linolenic: Double = 0, ricinoleic: Double = 0
    ) -> Ingredient {
        let ing = Ingredient(name: name, unit: "g")
        ing.sapValue = naohSap
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
