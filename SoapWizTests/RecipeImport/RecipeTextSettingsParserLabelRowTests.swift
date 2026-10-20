import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe text settings parser, labels, purities and lye ratio")
struct RecipeTextSettingsParserLabelRowTests {

    // MARK: - Labels and values on consecutive lines

    private static let mendruCalcOCR = """
        Sosa cáustica (NaOH) 73g 9.1%
        Yodo INS TOTAL
        67 131 804g 100.0%
        Sobreengrasado Concentración
        8% 30%
        Reescalar Fórmula 2000g
        """

    @Test func parse_LabelRowOverValueRow_PairsThemLeftToRight() throws {
        let settings = RecipeTextSettingsParser.parse(Self.mendruCalcOCR)

        #expect(settings.superFat == 8)
        let parts = try #require(settings.waterParts)
        #expect(abs(parts - 70.0 / 30.0) < 1e-9)
    }

    @Test func superFat_LabelAloneOverItsValue_IsRead() {
        #expect(RecipeTextSettingsParser.superFat(in: "Superfat\n8%") == 8)
    }

    @Test func parse_MoreLabelsThanValues_ReadsNothing() {
        let settings = RecipeTextSettingsParser.parse("Sobreengrasado Concentración\n8%")

        #expect(settings.superFat == nil)
        #expect(settings.waterParts == nil)
    }

    @Test func parse_MoreValuesThanLabels_ReadsNothing() {
        let settings = RecipeTextSettingsParser.parse("Sobreengrasado\n8% 30%")

        #expect(settings.superFat == nil)
    }

    @Test func parse_IngredientLineBetweenLabelsAndValues_ReadsNothing() {
        let settings = RecipeTextSettingsParser.parse("Sobreengrasado Concentración\nOlive Oil 400 g\n8% 30%")

        #expect(settings.superFat == nil)
        #expect(settings.waterParts == nil)
    }

    @Test func parse_BlankLineBetweenLabelsAndValues_StillPairs() {
        #expect(RecipeTextSettingsParser.parse("Sobreengrasado Concentración\n\n8% 30%").superFat == 8)
    }

    @Test func fragrancePercentage_LabelRowOverValueRow_IsRead() {
        #expect(RecipeTextSettingsParser.fragrancePercentage(in: "Superfat Fragrance load\n5% 3%") == 3)
    }

    // MARK: - Superfat typo

    @Test(arguments: ["sobreengasado 10 %", "Sobreengasado: 10%", "10% sobreengasado", "sobreengrasado 10 %"])
    func superFat_MissingRInSpanishKeyword_IsRead(_ text: String) {
        #expect(RecipeTextSettingsParser.superFat(in: text) == 10)
    }

    // MARK: - Purity wording

    @Test(arguments: [
        ("NaOH Weight at 99 % Purity\t14.67 oz\t415.97 g", 99.0),
        ("KOH Weight at 90 % Purity\t2.95 oz\t83.76 g", 90.0)
    ])
    func lyePurity_WeightAtPurityWording_IsRead(_ text: String, _ expected: Double) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == expected)
    }

    @Test func lyePurity_BothWeightAtPurityLines_StaysNil() {
        let text = "NaOH Weight at 99 % Purity\t0.63 oz\nKOH Weight at 90 % Purity\t2.95 oz"

        #expect(RecipeTextSettingsParser.lyePurity(in: text) == nil)
    }

    @Test func weightPurity_NamesTheLye() {
        let text = "NaOH Weight at 99 % Purity\t0.63 oz\nKOH Weight at 90 % Purity\t2.95 oz"

        #expect(RecipeTextSettingsParser.weightPurity(of: "NaOH", in: text) == 99)
        #expect(RecipeTextSettingsParser.weightPurity(of: "KOH", in: text) == 90)
    }

    @Test func weightPurity_LyeNotStated_IsNil() {
        #expect(RecipeTextSettingsParser.weightPurity(of: "KOH", in: "NaOH Weight at 99 % Purity\t0.63 oz") == nil)
    }

    // MARK: - Dual lye ratio

    @Test func kohPercentage_NaOHFirst_IsTheSecondShare() {
        #expect(RecipeTextSettingsParser.kohPercentage(in: "NaOH / KOH Ratio\t\t25 % / 75 %") == 75)
    }

    @Test func kohPercentage_KOHFirst_IsTheFirstShare() {
        #expect(RecipeTextSettingsParser.kohPercentage(in: "KOH / NaOH Ratio 70% / 30%") == 70)
    }

    @Test func kohPercentage_SharesNotSummingToAHundred_IsNil() {
        #expect(RecipeTextSettingsParser.kohPercentage(in: "NaOH / KOH Ratio 25 % / 70 %") == nil)
    }

    @Test func kohPercentage_OneShareOnly_IsNil() {
        #expect(RecipeTextSettingsParser.kohPercentage(in: "NaOH / KOH Ratio 25 %") == nil)
    }

    @Test func parse_HybridText_CarriesTheSharesAndPurities() {
        let text = """
            NaOH Weight at 99 % Purity\t0.63 oz\t17.91 g
            KOH Weight at 90 % Purity\t2.95 oz\t83.76 g
            NaOH / KOH Ratio\t\t25 % / 75 %
            """
        let settings = RecipeTextSettingsParser.parse(text)

        #expect(settings.kohPercentage == 75)
        #expect(settings.naohPurity == 99)
        #expect(settings.kohPurity == 90)
        #expect(settings.lyePurity == nil)
    }

    // MARK: - Spanish lye names in text

    @Test(arguments: ["Sosa cáustica (NaOH) 73g", "sosa: 99.2 g", "Hidróxido de sodio 100 g", "soda cáustica 100 g"])
    func lyeType_SpanishSodium_IsNaOH(_ text: String) {
        #expect(RecipeTextSettingsParser.lyeType(in: text) == "NaOH")
    }

    @Test(arguments: ["potasa cáustica 100 g", "Potasa 100 g", "hidróxido de potasio 100 g"])
    func lyeType_SpanishPotassium_IsKOH(_ text: String) {
        #expect(RecipeTextSettingsParser.lyeType(in: text) == "KOH")
    }

    @Test func lyeType_BareSodaInText_IsNotALye() {
        #expect(RecipeTextSettingsParser.lyeType(in: "soda: 99.2") == nil)
    }
}
