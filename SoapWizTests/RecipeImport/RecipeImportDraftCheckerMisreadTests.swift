import Testing
import Foundation
@testable import SoapWiz

/// Each case replays a text from the device evaluation, paired with what the
/// model actually returned for it.
@Suite("Recipe import draft checker, evaluation misreads")
struct RecipeImportDraftCheckerMisreadTests {

    // MARK: - Percentage column read as weights

    private static let soapCalcText = """
        Total oil weight\t1000 g
        1\t\tOlive Oil\t40.00\t0.882\t14.11\t400.00
        2\t\tCoconut Oil, 76 deg\t25.00\t0.551\t8.82\t250.00
        3\t\tShea Butter\t15.00\t0.331\t5.29\t150.00
        4\t\tCastor Oil\t5.00\t0.110\t1.76\t50.00
        5\t\tAlmond Oil, sweet\t15.00\t0.331\t5.29\t150.00
        """

    @Test func checked_PercentageColumnReadAsGrams_BecomesAPercentageRecipe() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 40, unit: "g"),
                ImportedIngredient(name: "Coconut", amount: 25, unit: "g"),
                ImportedIngredient(name: "Shea", amount: 15, unit: "g"),
                ImportedIngredient(name: "Castor", amount: 5, unit: "g"),
                ImportedIngredient(name: "Almond", amount: 15, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: 1000,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: Self.soapCalcText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.allSatisfy { $0.unit == "%" })
        #expect(checked.oils.map(\.amount) == [40, 25, 15, 5, 15])
        #expect(checked.batchSize == 1000)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_GenuineHundredGramRecipe_StaysAWeightRecipe() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 70, unit: "g"),
                ImportedIngredient(name: "Coconut Oil", amount: 30, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: 100,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.checked(
            draft, against: "Olive Oil 70 g\nCoconut Oil 30 g\nBatch size 100 g"
        )

        #expect(!checked.amountsArePercentages)
        #expect(checked.oils.allSatisfy { $0.unit == "g" })
    }

    @Test func checked_WeightRecipeWithoutAStatedBatch_StaysAWeightRecipe() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 70, unit: "g"),
                ImportedIngredient(name: "Coconut Oil", amount: 30, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 70 g\nCoconut Oil 30 g")

        #expect(!checked.amountsArePercentages)
    }

    // MARK: - Rows in the wrong section

    private static let saltBarText = """
        Water + Lye
        11.27 oz Water
        5.63 oz 98% Purity NaOH
        Oils
        40 oz Coconut Oil, 76 deg
        Additives + Additional Ingredients
        40 ounce Fine sea salt
        4 tablespoon French Green Clay
        2 tablespoon Honey
        1 ounce Patcholi EO
        1.50 ounce Ylang Ylang EO
        Superfat %\t25%
        """

    @Test func checked_SaltBarRowsUnderOils_MoveToTheirSections() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Coconut Oil, 76 deg", amount: 40, unit: "oz"),
                ImportedIngredient(name: "Patcholi EO", amount: 1, unit: "ounce"),
                ImportedIngredient(name: "Ylang Ylang EO", amount: 1.5, unit: "ounce"),
                ImportedIngredient(name: "French Green Clay", amount: 4, unit: "tablespoons"),
                ImportedIngredient(name: "Honey", amount: 2, unit: "tablespoons")
            ],
            additives: [ImportedIngredient(name: "Fine sea salt", amount: 40, unit: "ounce")],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "oz"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: Self.saltBarText)

        #expect(checked.oils.map(\.name) == ["Coconut Oil, 76 deg"])
        #expect(checked.fragrances.map(\.name) == ["Patcholi EO", "Ylang Ylang EO"])
        #expect(checked.additives.map(\.name) == ["Fine sea salt", "French Green Clay", "Honey"])
    }

    @Test func checked_ScentUnderOils_MovesToFragrances() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Palm Oil", amount: 2.24, unit: "oz"),
                ImportedIngredient(name: "Scent", amount: 0.75, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "2.24 oz Palm Oil\n0.75 ounce Scent")

        #expect(checked.oils.map(\.name) == ["Palm Oil"])
        #expect(checked.fragrances.map(\.name) == ["Scent"])
    }

    @Test func checked_BlogRowsUnderOils_MoveToTheirSections() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Coconut Oil", amount: 13.6, unit: "oz"),
                ImportedIngredient(name: "Honey Oatmeal Fragrance Oil", amount: 2.5, unit: "oz"),
                ImportedIngredient(name: "Colloidal Oatmeal", amount: 1, unit: "tsp"),
                ImportedIngredient(name: "Titanium Dioxide", amount: 0, unit: nil),
                ImportedIngredient(name: "Sodium Lactate", amount: 1, unit: "tbsp")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "oz"
        )
        let text = "13.6 oz. Coconut Oil\n2.5 oz. Honey Oatmeal Fragrance Oil\n1 tsp. Colloidal Oatmeal\n"
            + "1 Tbsp. Sodium Lactate\nTitanium Dioxide"

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        #expect(checked.oils.map(\.name) == ["Coconut Oil"])
        #expect(checked.fragrances.map(\.name) == ["Honey Oatmeal Fragrance Oil"])
        #expect(checked.additives.map(\.name) == ["Colloidal Oatmeal", "Titanium Dioxide", "Sodium Lactate"])
    }

    @Test(arguments: [
        "tsp", "Tsp.", "tbsp", "teaspoon", "teaspoons", "tablespoon", "Tablespoons",
        "cup", "cups", "ml", "l", "drop", "drops", "ml."
    ])
    func checked_OilInAVolumeUnit_MovesToAdditives(_ unit: String) {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g"),
                ImportedIngredient(name: "Mystery Powder", amount: 2, unit: unit)
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g\nMystery Powder 2")

        #expect(checked.oils.map(\.name) == ["Olive Oil"])
        #expect(checked.additives.map(\.name) == ["Mystery Powder"])
    }

    @Test func checked_FragranceInASpoonUnit_GoesToFragrancesNotAdditives() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g"),
                ImportedIngredient(name: "Lavender Essential Oil", amount: 2, unit: "tsp")
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g\nLavender Essential Oil 2 tsp")

        #expect(checked.additives.isEmpty)
        #expect(checked.fragrances.map(\.name) == ["Lavender Essential Oil"])
    }

    @Test func checked_OilsButtersAndWaxes_StayWhereTheModelPutThem() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Shea Butter", amount: 100, unit: "g"),
                ImportedIngredient(name: "Beeswax", amount: 10, unit: "g"),
                ImportedIngredient(name: "Milk Thistle Oil", amount: 20, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(
            draft, against: "Shea Butter 100 g\nBeeswax 10 g\nMilk Thistle Oil 20 g"
        )

        #expect(checked.oils.count == 3)
        #expect(checked.additives.isEmpty)
    }

    @Test(arguments: [
        ("Scent", RecipeIngredientRole?.some(.fragrance)),
        ("Scents", .fragrance),
        ("Fragrance", .fragrance),
        ("Fragrances", .fragrance),
        ("Titanium Dioxide", .additive),
        ("Lavender", nil)
    ])
    func evidentRole_NewWording_IsRead(_ name: String, _ expected: RecipeIngredientRole?) {
        #expect(ImportedIngredientName.evidentRole(of: name) == expected)
    }

    // MARK: - Duplicate rows

    @Test func checked_RepeatedFragranceRows_AreCollapsed() {
        let row = ImportedIngredient(name: "Fragrance Oil", amount: 1, unit: "tsp")
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g")],
            additives: Array(repeating: row, count: 12).map { ImportedIngredient(name: $0.name, amount: $0.amount, unit: $0.unit) },
            fragrances: (0..<7).map { _ in ImportedIngredient(name: "Fragrance Oil", amount: 1, unit: "tsp") },
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g\nFragrance Oil 1 tsp")

        #expect(checked.fragrances.count == 1)
        #expect(checked.additives.isEmpty)
    }

    @Test func checked_RepeatedSpreadsheetFragrance_IsKeptOnce() {
        let draft = RecipeImportDraft.mock(
            fragrances: [
                ImportedIngredient(name: "Lavender EO", amount: 24, unit: "g"),
                ImportedIngredient(name: "lavender eo", amount: 24, unit: "G")
            ]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Lavender EO 3% 24")

        #expect(checked.fragrances.count == 1)
        #expect(checked.fragrances.first?.name == "Lavender EO")
    }

    @Test func checked_SameNameWithADifferentAmountOrUnit_IsKept() {
        let draft = RecipeImportDraft.mock(
            fragrances: [
                ImportedIngredient(name: "Lavender EO", amount: 24, unit: "g"),
                ImportedIngredient(name: "Lavender EO", amount: 12, unit: "g"),
                ImportedIngredient(name: "Lavender EO", amount: 24, unit: "oz"),
                ImportedIngredient(name: "Lavender EO", amount: 24, unit: nil)
            ]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Lavender EO 24 g 12 oz")

        #expect(checked.fragrances.count == 4)
    }

    @Test func checked_RowInOilsAndAdditives_StaysInBoth() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g")],
            additives: [ImportedIngredient(name: "Olive Oil", amount: 500, unit: "g")],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g")

        #expect(checked.oils.count == 1)
        #expect(checked.additives.count == 1)
    }

    // MARK: - Batch unit from a mould

    @Test func checked_MouldSizeBesideOunceOils_ClearsTheBatchSize() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Coconut Oil", amount: 13.6, unit: "oz"),
                ImportedIngredient(name: "Olive Oil", amount: 13.6, unit: "oz"),
                ImportedIngredient(name: "Palm Oil", amount: 9.5, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: 5,
            batchUnit: "lb"
        )
        let text = "5-Pound Wood Mold\n13.6 oz. Coconut Oil\n13.6 oz. Olive Oil\n9.5 oz. Palm Oil"

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        #expect(checked.batchUnit == "oz")
        #expect(checked.batchSize == nil)
    }

    @Test func checked_BatchSizeMatchingTheOilTotal_IsKept() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 600, unit: "g"),
                ImportedIngredient(name: "Coconut Oil", amount: 400, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: 1000,
            batchUnit: "g"
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 600 g\nCoconut Oil 400 g\nTotal 1000 g")

        #expect(checked.batchSize == 1000)
    }

    // MARK: - Water with a note

    @Test func checked_WaterForDilutionAsNeeded_IsDropped() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Coconut oil", amount: 500, unit: "g")],
            additives: [
                ImportedIngredient(name: "Glycerin", amount: 400, unit: "g"),
                ImportedIngredient(name: "Distilled water for dilution, as needed", amount: 0, unit: nil),
                ImportedIngredient(name: "Water (as needed)", amount: 0, unit: nil)
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(
            draft, against: "Coconut oil 500 g\nGlycerin 400 g\nDistilled water for dilution, as needed"
        )

        #expect(checked.additives.map(\.name) == ["Glycerin"])
    }

    @Test func checked_RoseWaterAndWaterlikeNames_AreKept() {
        let draft = RecipeImportDraft.mock(
            additives: [
                ImportedIngredient(name: "Rose water", amount: 50, unit: "g"),
                ImportedIngredient(name: "Rose water", amount: 0, unit: nil),
                ImportedIngredient(name: "Waterlily Extract", amount: 0, unit: nil)
            ]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Rose water 50 g")

        #expect(checked.additives.count == 3)
    }

    // MARK: - Lye purity

    @Test func checked_StatedPurity_IsSetOnTheDraft() {
        let draft = RecipeImportDraft.mock(lyeType: "KOH")

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 50%\n2.09 oz 90% Purity KOH")

        #expect(checked.lyePurity == 90)
    }

    @Test func checked_NoPurityInText_LeavesItNil() {
        let checked = RecipeImportDraftChecker.checked(.mock(), against: "Olive Oil 70%\nCoconut Oil 30%")

        #expect(checked.lyePurity == nil)
    }

    // MARK: - Compound pounds and ounces

    @Test func checked_CombinedPoundsAndOunces_KeepsTheAmountFromTheSanitizedText() {
        let sanitized = RecipeTextSanitizer.sanitize("1 lb 4 oz tallow\n8 oz coconut oil\n4 oz olive oil")
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "tallow", amount: 20, unit: "oz"),
                ImportedIngredient(name: "coconut oil", amount: 8, unit: "oz"),
                ImportedIngredient(name: "olive oil", amount: 4, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: sanitized.text)

        #expect(checked.oils.first?.amount == 20)
    }
}
