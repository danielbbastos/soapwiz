import Testing
import Foundation
@testable import SoapWiz

/// Oil tables read by their column headers, and the other checker corrections
/// found in the same device evaluation. Each text is trimmed from the real one,
/// and the draft is what the model actually returned for it.
@Suite("Recipe import draft checker, oil tables")
struct RecipeImportDraftCheckerOilTableTests {

    // MARK: - Soapmaking Friend, hybrid lye

    private static let hybridText = """
        Recipe Totals
        NaOH Weight at 99 % Purity\t0.63 oz\t17.91 g
        KOH Weight at 90 % Purity\t2.95 oz\t83.76 g
        Lye Weight\t3.59 oz\t101.67 g
        Oil Weight\t19 oz\t538.64 g
        Super Fat\t\t5 %
        Total Batch Weight\t32 oz\t907.15 g
        NaOH / KOH Ratio\t\t25 % / 75 %
        Recipe Oils, Fats and Waxes
        Oil\t%\tOunces\tGrams

        Tallow Beef
        \t73.68\t14\t396.89

        Castor Oil
        \t10.53\t2\t56.7

        Sunflower Oil
        \t10.53\t2\t56.7

        Cocoa Butter
        \t5.26\t1\t28.35
        Total\t100\t19\t538.64
        Custom Additives
        Add with the liquid

        Sugar
        \t0.64 oz\t18.14 g
        """

    private static func hybridDraft() -> RecipeImportDraft {
        .mock(
            oils: [
                ImportedIngredient(name: "Tallow Beef", amount: 14, unit: "g"),
                ImportedIngredient(name: "Castor Oil", amount: 2, unit: "g"),
                ImportedIngredient(name: "Sunflower Oil", amount: 2, unit: "g"),
                ImportedIngredient(name: "Cocoa Butter", amount: 1, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "g",
            lyeType: "NaOH",
            waterParts: 2
        )
    }

    @Test func checked_HybridTable_ReadsSharesAndGramsColumn() throws {
        let checked = RecipeImportDraftChecker.checked(Self.hybridDraft(), against: Self.hybridText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.map(\.amount) == [73.68, 10.53, 10.53, 5.26])
        #expect(checked.oils.allSatisfy { $0.unit == "%" })
        #expect(checked.batchUnit == "g")
        let batchSize = try #require(checked.batchSize)
        #expect(abs(batchSize - 538.64) < 0.01)
    }

    @Test func checked_HybridTable_UsesTheOuncesColumnWhenTheDraftIsInOunces() {
        var draft = Self.hybridDraft()
        draft.batchUnit = "oz"

        let checked = RecipeImportDraftChecker.checked(draft, against: Self.hybridText)

        #expect(checked.batchUnit == "oz")
        #expect(checked.batchSize == 19)
    }

    @Test func checked_HybridLyeRatio_SetsTheSharesAndEachPurity() {
        let checked = RecipeImportDraftChecker.checked(Self.hybridDraft(), against: Self.hybridText)

        #expect(checked.kohPercentage == 75)
        #expect(checked.kohPurity == 90)
        #expect(checked.naohPurity == 99)
        #expect(checked.lyeType == nil)
        #expect(checked.lyePurity == nil)
        #expect(checked.superFat == 5)
    }

    // MARK: - Soapmaking Friend, hot process

    private static let hotProcessText = """
        Recipe Totals
        NaOH Weight at 99 % Purity\t14.67 oz\t415.97 g
        Oil Weight\t100 oz\t2834.95 g
        Total Batch Weight\t166.76 oz\t4727.5 g
        Recipe Oils, Fats and Waxes
        Oil\t%\tOunces\tGrams

        Olive Oil
        \t54.1\t54.1\t1533.71

        Coconut Oil, 76 deg
        \t25\t25\t708.74

        Mango Seed Butter
        \t10.9\t10.9\t309.01

        Castor Oil
        \t10\t10\t283.5
        Super Fat after cook
        \t5\t5 oz\t141.75
        Total\t100+5\t105\t2976.7
        Custom Additives
        """

    @Test func checked_HotProcessTable_IgnoresThePostCookSuperfatRow() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 54.1, unit: "oz"),
                ImportedIngredient(name: "Coconut Oil, 76 deg", amount: 25, unit: "oz"),
                ImportedIngredient(name: "Mango Seed Butter", amount: 10.9, unit: "oz"),
                ImportedIngredient(name: "Castor Oil", amount: 10, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: 105,
            batchUnit: "oz"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: Self.hotProcessText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.map(\.amount) == [54.1, 25, 10.9, 10])
        #expect(checked.batchUnit == "oz")
        #expect(checked.batchSize == 100)
    }

    // MARK: - Soapmaking Friend, grams only

    private static let gramsText = """
        Recipe Totals
        Oil Weight\t1541.42 g
        Total Batch Weight\t2396.68 g
        Recipe Oils, Fats and Waxes
        Oil\t%\tGrams

        Coconut Oil, 76 deg
        \t32\t493.25

        Olive Oil
        \t32\t493.25

        Palm Oil
        \t32\t493.25

        Castor Oil
        \t4\t61.66
        Total\t100\t1541.42
        """

    @Test func checked_GramsTable_TakesTheOilTotalNotTheBatchWeight() throws {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Coconut Oil, 76 deg", amount: 32, unit: "g"),
                ImportedIngredient(name: "Olive Oil", amount: 32, unit: "g"),
                ImportedIngredient(name: "Palm Oil", amount: 32, unit: "g"),
                ImportedIngredient(name: "Castor Oil", amount: 4, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: 2396.68,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: Self.gramsText)

        #expect(checked.oils.map(\.amount) == [32, 32, 32, 4])
        let batchSize = try #require(checked.batchSize)
        #expect(abs(batchSize - 1541.42) < 0.05)
    }

    // MARK: - SoapCalc

    private static let soapCalcText = """
        Total oil weight\t1000 g
        Item\tPounds\tOunces\tGrams
        Oils\t2.205\t35.27\t1000.00
        #\t✓\tOil/Fat\t%\tPounds\tOunces\tGrams
        1\t\tOlive Oil\t40.00\t0.882\t14.11\t400.00
        2\t\tCoconut Oil, 76 deg\t25.00\t0.551\t8.82\t250.00
        3\t\tShea Butter\t15.00\t0.331\t5.29\t150.00
        4\t\tCastor Oil\t5.00\t0.110\t1.76\t50.00
        5\t\tAlmond Oil, sweet\t15.00\t0.331\t5.29\t150.00
        \t\tTotals\t100.00\t2.205\t35.27\t1000.00
        """

    private static func soapCalcDraft(unit: String) -> RecipeImportDraft {
        .mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 400, unit: unit),
                ImportedIngredient(name: "Coconut Oil", amount: 250, unit: unit),
                ImportedIngredient(name: "Shea Butter", amount: 150, unit: unit),
                ImportedIngredient(name: "Castor Oil", amount: 50, unit: unit),
                ImportedIngredient(name: "Almond Oil", amount: 150, unit: unit)
            ],
            amountsArePercentages: false,
            batchSize: 1000,
            batchUnit: unit
        )
    }

    @Test func checked_SoapCalcTable_ReadsSharesBesideTheRowNumber() {
        let checked = RecipeImportDraftChecker.checked(Self.soapCalcDraft(unit: "g"), against: Self.soapCalcText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.map(\.amount) == [40, 25, 15, 5, 15])
        #expect(checked.batchSize == 1000)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_SoapCalcTable_TotalsThePoundsColumnForAPoundsDraft() throws {
        let checked = RecipeImportDraftChecker.checked(Self.soapCalcDraft(unit: "lb"), against: Self.soapCalcText)

        #expect(checked.batchUnit == "lb")
        let batchSize = try #require(checked.batchSize)
        #expect(abs(batchSize - 2.205) < 0.001)
    }

    // MARK: - Tables that do not apply

    @Test func oilTableRecipe_DraftOilMissingFromTheTable_IsNil() {
        var draft = Self.soapCalcDraft(unit: "g")
        draft.oils.append(ImportedIngredient(name: "Palm Oil", amount: 10, unit: "g"))

        #expect(RecipeImportDraftChecker.oilTableRecipe(draft, in: Self.soapCalcText) == nil)
    }

    @Test func oilTableRecipe_SharesThatAreNotAWholeBlend_IsNil() {
        let text = """
            Oil\t%\tGrams
            Olive Oil\t40\t400
            Coconut Oil\t25\t250
            """
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 400, unit: "g"),
                ImportedIngredient(name: "Coconut Oil", amount: 250, unit: "g")
            ],
            amountsArePercentages: false
        )

        #expect(RecipeImportDraftChecker.oilTableRecipe(draft, in: text) == nil)
    }

    @Test func oilTableRecipe_TextWithoutAHeader_IsNil() {
        let draft = RecipeImportDraft.mock()

        #expect(RecipeImportDraftChecker.oilTableRecipe(draft, in: "Olive Oil 70%\nCoconut Oil 30%") == nil)
    }

    @Test func oilTableRecipe_ValueLineWithAPercentAndWeights_IsNotAHeader() {
        let text = "NaOH Weight at 99 % Purity\t14.67 oz\t415.97 g\nOlive Oil\t70\t700\nCoconut Oil\t30\t300"

        #expect(RecipeImportDraftChecker.oilTableRecipe(.mock(), in: text) == nil)
    }

    @Test func oilTableRecipe_NoOils_IsNil() {
        #expect(RecipeImportDraftChecker.oilTableRecipe(.mock(oils: []), in: Self.soapCalcText) == nil)
    }

    // MARK: - Spanish lye and water rows

    @Test func checked_SpanishSodaAndAguaRows_AreNotOils() {
        let text = """
            Ingredientes:
            aceite de oliva 405 gr
            cera de abejas 20 gr
            aceite de coco 250
            aceite de ricino 45 gr

            soda: 99.2
            agua: 255
            """
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "aceite de oliva", amount: 405, unit: "g"),
                ImportedIngredient(name: "cera de abejas", amount: 20, unit: "g"),
                ImportedIngredient(name: "aceite de coco", amount: 250, unit: "g"),
                ImportedIngredient(name: "aceite de ricino", amount: 45, unit: "g"),
                ImportedIngredient(name: "soda", amount: 99.2, unit: "g"),
                ImportedIngredient(name: "agua", amount: 255, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            lyeType: nil,
            superFat: nil,
            waterParts: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        #expect(checked.oils.map(\.name) == ["aceite de oliva", "cera de abejas", "aceite de coco", "aceite de ricino"])
        #expect(checked.lyeType == "NaOH")
    }

    // MARK: - Decimals without a leading zero

    @Test func checked_AmountWrittenWithoutALeadingZero_IsKept() throws {
        let text = "Olive oil 10 oz\nCoconut Oil 12.5 oz\nCanola .5 oz\n\n11.3 oz Water"
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive oil", amount: 10, unit: "oz"),
                ImportedIngredient(name: "Coconut Oil", amount: 12.5, unit: "oz"),
                ImportedIngredient(name: "Canola", amount: 0.5, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "oz"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        let canola = try #require(checked.oils.first { $0.name == "Canola" })
        #expect(canola.amount == 0.5)
    }
}
