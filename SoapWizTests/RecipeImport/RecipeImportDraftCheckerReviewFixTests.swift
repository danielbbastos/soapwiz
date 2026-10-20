import Testing
import Foundation
@testable import SoapWiz

/// Corrections to the draft checker found in review: the percentage flip, waxes
/// and water rows.
@Suite("Recipe import draft checker, review fixes")
struct RecipeImportDraftCheckerReviewFixTests {

    // MARK: - Shares read as weights

    private static let soapCalcText = """
        Total oil weight\t1000 g
        1\t\tOlive Oil\t40.00\t0.882\t14.11\t400.00
        2\t\tCoconut Oil, 76 deg\t25.00\t0.551\t8.82\t250.00
        3\t\tShea Butter\t15.00\t0.331\t5.29\t150.00
        4\t\tCastor Oil\t5.00\t0.110\t1.76\t50.00
        5\t\tAlmond Oil, sweet\t15.00\t0.331\t5.29\t150.00
        """

    @Test(arguments: [("Total 6.25 lb", 6.25, "lb"), ("Total 2834.95 g", 2834.95, "g")])
    func readingSharesAsPercentages_HundredOunceRecipeWithBatchInAnotherUnit_StaysAWeightRecipe(
        _ total: String, _ batchSize: Double, _ batchUnit: String
    ) {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 54.1, unit: "oz"),
                ImportedIngredient(name: "Coconut Oil", amount: 25, unit: "oz"),
                ImportedIngredient(name: "Mango Butter", amount: 10.9, unit: "oz"),
                ImportedIngredient(name: "Castor Oil", amount: 10, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: batchSize,
            batchUnit: batchUnit
        )
        let text = "Olive Oil 54.1 oz\nCoconut Oil 25 oz\nMango Butter 10.9 oz\nCastor Oil 10 oz\n\(total)"

        let checked = RecipeImportDraftChecker.readingSharesAsPercentages(draft, in: text)

        #expect(!checked.amountsArePercentages)
        #expect(checked.oils.allSatisfy { $0.unit == "oz" })
    }

    @Test func readingSharesAsPercentages_SoapCalcLinesWithoutUnits_StillFlips() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 40, unit: "g"),
                ImportedIngredient(name: "Coconut Oil", amount: 25, unit: "g"),
                ImportedIngredient(name: "Shea Butter", amount: 15, unit: "g"),
                ImportedIngredient(name: "Castor Oil", amount: 5, unit: "g"),
                ImportedIngredient(name: "Almond Oil", amount: 15, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: 1000,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.readingSharesAsPercentages(draft, in: Self.soapCalcText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.allSatisfy { $0.unit == "%" })
    }

    // MARK: - Waxes

    @Test func checked_BeeswaxInASpoonUnit_StaysAnOil() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g"),
                ImportedIngredient(name: "Beeswax", amount: 1, unit: "tbsp")
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g\nBeeswax 1 tbsp")

        #expect(checked.oils.map(\.name) == ["Olive Oil", "Beeswax"])
        #expect(checked.additives.isEmpty)
    }

    // MARK: - Water with a note

    @Test(arguments: [
        "Distilled water for dilution, as needed", "Water (as needed)", "Water", "Water, as required", "Water - if needed",
        "Water - as needed", "Water – for dilution"
    ])
    func isWaterWithNote_NoteAfterTheWaterName_IsTrue(_ name: String) {
        #expect(ImportedIngredientName.isWaterWithNote(name))
    }

    @Test(arguments: ["Water Kefir", "Water Soluble Dye", "Rose Water", "Waterlily Extract", "Water-Soluble Dye"])
    func isWaterWithNote_AnotherIngredientStartingWithWater_IsFalse(_ name: String) {
        #expect(!ImportedIngredientName.isWaterWithNote(name))
    }

    @Test func checked_ZeroAmountWaterKefir_IsKept() {
        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Water Kefir", amount: 0, unit: nil)]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Water Kefir")

        #expect(checked.additives.map(\.name) == ["Water Kefir"])
    }
}
