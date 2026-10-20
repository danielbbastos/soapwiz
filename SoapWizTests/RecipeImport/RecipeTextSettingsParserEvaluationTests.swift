import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe text settings parser, evaluation misreads")
struct RecipeTextSettingsParserEvaluationTests {

    // MARK: - Superfat range

    @Test func superFat_SaltBarValue_IsRead() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat %\t25%") == 25)
    }

    @Test func superFat_AboveThirty_IsStillRejected() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat 35%") == nil)
    }

    // MARK: - Spanish

    @Test(arguments: [
        ("Sobreengrasado: 7%", 7.0),
        ("Sobreengrasado: 7,5%", 7.5),
        ("sobre-engrasado 5%", 5.0),
        ("SOBREENGRASADO 6", 6.0),
        ("Sobreengrase: 8%", 8.0),
        ("7% sobreengrasado", 7.0)
    ])
    func superFat_SpanishKeyword_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.superFat(in: text) == expected)
    }

    @Test(arguments: [
        "Concentración: 30%",
        "concentracion 30%",
        "Concentración de sosa: 30 %",
        "Concentración de la lejía 30%",
        "CONCENTRACIÓN: 30,0%"
    ])
    func waterParts_SpanishConcentration_IsConvertedToParts(_ text: String) throws {
        let parts = try #require(RecipeTextSettingsParser.waterParts(in: text))
        #expect(abs(parts - 70.0 / 30.0) < 0.0001)
    }

    @Test func waterParts_EnglishBareConcentration_IsNotRead() {
        #expect(RecipeTextSettingsParser.waterParts(in: "Concentration 30%") == nil)
    }

    @Test func waterParts_LyeConcentrationMeaningPurity_StaysRejected() {
        #expect(RecipeTextSettingsParser.waterParts(in: "Lye concentration 90%") == nil)
    }

    @Test func parse_SpanishRecipeText_ReadsBothSettings() throws {
        let text = "Sosa cáustica (NaOH)\t127,6 g\nAgua\t300 g\nSobreengrasado: 7%\nConcentración: 30%"

        let settings = RecipeTextSettingsParser.parse(text)

        #expect(settings.superFat == 7)
        let parts = try #require(settings.waterParts)
        #expect(abs(parts - 70.0 / 30.0) < 0.0001)
    }

    // MARK: - Lye purity

    @Test(arguments: [
        ("5.63 oz 98% Purity NaOH", 98.0),
        ("2.09 oz 90% Purity KOH", 90.0),
        ("98% purity NaOH", 98.0),
        ("KOH (90%) 246 g", 90.0),
        ("NaOH 99%", 99.0),
        ("KOH 90 %", 90.0),
        ("KOH: 90,5%", 90.5),
        ("Lye purity: 90%\nKOH", 90.0),
        ("purity: 90%", 90.0),
        ("90% KOH", 90.0),
        ("Potassium Hydroxide (90%)", 90.0)
    ])
    func lyePurity_StatedPhrase_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == expected)
    }

    @Test(arguments: ["100% KOH", "100% NaOH", "NaOH 100%", "NaOH (100%)", "100 % sodium hydroxide"])
    func lyePurity_BareHundredBesideTheLye_IsNotPurity(_ text: String) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == nil)
    }

    @Test(arguments: [
        ("100% pure NaOH", 100.0),
        ("100% purity KOH", 100.0),
        ("purity: 100%", 100.0),
        ("99% NaOH", 99.0),
        ("KOH 98%", 98.0),
        ("90% KOH", 90.0)
    ])
    func lyePurity_PurityWordOrBelowHundred_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == expected)
    }

    @Test func lyePurity_LyeConcentration_IsNotPurity() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "Lye concentration 90%\nSuperfat 5%") == nil)
    }

    @Test func lyePurity_LyeCalcPage_ReadsThePurityNotTheConcentration() {
        let text = "2.09 oz 90% Purity KOH\nSuperfat %\t5%\nLye concentration\t90%"
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == 90)
    }

    @Test(arguments: ["NaOH 30%", "KOH 20%", "49% NaOH", "NaOH 101%"])
    func lyePurity_OutOfRange_IsNil(_ text: String) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == nil)
    }

    @Test func lyePurity_HybridLyeWithTwoPurities_IsNil() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "NaOH 99% 100 g\nKOH 90% 50 g") == nil)
    }

    @Test func lyePurity_HybridLyeWithOneBarePurity_IsNil() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "NaOH 100 g\nKOH 50 g\nPurity: 90%") == nil)
    }

    @Test func lyePurity_NoLyeNamed_IsNil() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "Olive Oil 70%\nCoconut Oil 30%") == nil)
    }

    @Test func parse_LyePurity_IsCarriedOnTheSettings() {
        #expect(RecipeTextSettingsParser.parse("4.18 oz Water\n2.09 oz 90% Purity KOH").lyePurity == 90)
    }
}
