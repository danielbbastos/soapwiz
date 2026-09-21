import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe text settings parser")
struct RecipeTextSettingsParserTests {

    // MARK: - Superfat

    @Test(arguments: [
        ("Lye: NaOH, 5% superfat, water:lye 2:1", 5.0),
        ("Use 4.5 oz lye (NaOH) at 6% superfat and replace the water", 6.0),
        ("Superfat: 5%     Lye: NaOH", 5.0),
        ("Superfat 3%", 3.0),
        ("SF 7", 7.0),
        ("lye discount of 4,5%", 4.5),
        ("8% super-fat", 8.0)
    ])
    func superFat_StatedPhrase_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.superFat(in: text) == expected)
    }

    @Test func superFat_KeywordWithoutANumber_IsNil() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat as usual, 4.5 oz lye") == nil)
    }

    @Test func superFat_NumberOnTheNextLine_IsNotClaimed() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat\n45% olive oil") == nil)
    }

    @Test func superFat_OutOfRange_IsNil() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat 45%") == nil)
    }

    // MARK: - Water

    @Test(arguments: [
        ("Lye: NaOH, 5% superfat, water:lye 2:1", 2.0),
        ("Water to lye ratio 2.5:1", 2.5),
        ("lye:water 1:2", 2.0),
        ("2:1 water to lye", 2.0),
        ("Superfat: 5%     Lye: NaOH     Water: 2.2 x lye", 2.2),
        ("water ratio 1.8", 1.8)
    ])
    func waterParts_StatedPhrase_IsRead(_ text: String, _ expected: Double) {
        let parts = RecipeTextSettingsParser.waterParts(in: text)
        #expect(parts.map { abs($0 - expected) < 0.0001 } == true)
    }

    @Test func waterParts_LyeConcentration_IsConvertedToParts() throws {
        let parts = try #require(RecipeTextSettingsParser.waterParts(in: "33% lye concentration"))
        #expect(abs(parts - 67.0 / 33.0) < 0.0001)
    }

    @Test func waterParts_NoRatio_IsNil() {
        #expect(RecipeTextSettingsParser.waterParts(in: "300 g distilled water, 131 g sodium hydroxide") == nil)
    }

    @Test func waterParts_OutOfRange_IsNil() {
        #expect(RecipeTextSettingsParser.waterParts(in: "water:lye 10:1") == nil)
    }

    // MARK: - Fragrance

    @Test(arguments: [("Fragrance load 3%", 3.0), ("fragrance: 5%", 5.0), ("4% scent", 4.0)])
    func fragrancePercentage_GenericPhrase_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.fragrancePercentage(in: text) == expected)
    }

    /// Two essential oils at 2% and 1% are a 3% load; reading the first as
    /// the load would be wrong, so per-oil rows are left to the proximity check.
    @Test func fragrancePercentage_PerOilPercentages_AreNotReadAsTheLoad() {
        #expect(RecipeTextSettingsParser.fragrancePercentage(in: "Lavender EO 2%, Tea Tree EO 1%") == nil)
    }

    // MARK: - Lye type

    @Test(arguments: [
        ("131 g sodium hydroxide", "NaOH"),
        ("Use 4.5 oz lye (NaOH)", "NaOH"),
        ("KOH 90% — 211 g", "KOH"),
        ("potassium hydroxide flakes", "KOH")
    ])
    func lyeType_OneKindNamed_IsRead(_ text: String, _ expected: String) {
        #expect(RecipeTextSettingsParser.lyeType(in: text) == expected)
    }

    @Test func lyeType_BothKindsNamed_IsNil() {
        #expect(RecipeTextSettingsParser.lyeType(in: "NaOH for the bar, KOH for the paste") == nil)
    }

    @Test func lyeType_NoneNamed_IsNil() {
        #expect(RecipeTextSettingsParser.lyeType(in: "Beeswax 30 g, shea butter 70 g") == nil)
    }

    @Test func lyeType_SodiumLactate_IsNotALye() {
        #expect(RecipeTextSettingsParser.lyeType(in: "Sodium Lactate 15 g") == nil)
    }

    // MARK: - Failor neutraliser

    @Test(arguments: [
        ("Borax — 25 g", CFMNeutralizer.borax),
        ("dissolve the sodium borate in water", CFMNeutralizer.borax),
        ("Boric Acid 20 g", CFMNeutralizer.boricAcid),
        ("boric acid for the neutraliser", CFMNeutralizer.boricAcid),
        ("neutralise the excess lye once cooked", CFMNeutralizer.boricAcid),
        ("neutralizing the excess lye at the end", CFMNeutralizer.boricAcid),
        ("made with the Catherine Failor method", CFMNeutralizer.boricAcid),
        ("Failor's liquid soap", CFMNeutralizer.boricAcid)
    ])
    func cfmNeutralizer_NamedOrMethodMentioned_IsRead(_ text: String, _ expected: CFMNeutralizer) {
        #expect(RecipeTextSettingsParser.cfmNeutralizer(in: text) == expected)
    }

    @Test func cfmNeutralizer_BoricAcidTakesPrecedenceOverBarePercentBorax() {
        #expect(RecipeTextSettingsParser.cfmNeutralizer(in: "boric acid and a pinch of borax") == .boricAcid)
    }

    @Test func cfmNeutralizer_NoneMentioned_IsNil() {
        #expect(RecipeTextSettingsParser.cfmNeutralizer(in: "Olive Oil 600 g, Coconut Oil 300 g") == nil)
    }

    @Test func cfmNeutralizer_BorageOil_IsNotBorax() {
        #expect(RecipeTextSettingsParser.cfmNeutralizer(in: "Borage Oil 20 g") == nil)
    }

    // MARK: - Proximity

    @Test func appears_NumberBesideKeyword_IsTrue() {
        let text = "Superfat (lye discount) around 5 for this one"
        #expect(RecipeTextSettingsParser.appears(
            5, near: RecipeTextSettingsParser.superFatKeyword, in: text, requiringPercent: false
        ))
    }

    @Test func appears_NumberFarFromKeyword_IsFalse() {
        let text = "Superfat as usual.\n\nOlive Oil — 600 g\nCoconut Oil — 300 g\nCastor Oil — 45 g"
        #expect(!RecipeTextSettingsParser.appears(
            45, near: RecipeTextSettingsParser.superFatKeyword, in: text, requiringPercent: false
        ))
    }

    @Test func appears_RequiringPercent_IgnoresABareNumber() {
        let text = "Fragrances:\nTea Tree EO         |       | 15"
        #expect(!RecipeTextSettingsParser.appears(
            15, near: RecipeTextSettingsParser.fragranceKeyword, in: text, requiringPercent: true
        ))
    }

    @Test func appears_RequiringPercent_AcceptsAPercentage() {
        let text = "Lavender Essential Oil 3% of oils"
        #expect(RecipeTextSettingsParser.appears(
            3, near: RecipeTextSettingsParser.fragranceKeyword, in: text, requiringPercent: true
        ))
    }
}
