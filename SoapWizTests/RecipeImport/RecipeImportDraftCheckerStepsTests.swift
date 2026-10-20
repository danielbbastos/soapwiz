import Testing
import Foundation
@testable import SoapWiz

/// The checker's ordered step list: the order itself, that running every step is
/// the default, and that skipping one step leaves only that rule undone.
@Suite("Recipe import draft checker, steps")
struct RecipeImportDraftCheckerStepsTests {

    private static let hybridText = """
        NaOH Weight at 99 % Purity\t0.63 oz\t17.91 g
        KOH Weight at 90 % Purity\t2.95 oz\t83.76 g
        Super Fat\t\t5 %
        NaOH / KOH Ratio\t\t25 % / 75 %
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

    private static let misfiledText = """
        Olive Oil 700 g
        Lavender Essential Oil 10 g
        Distilled Water 300 g
        """

    private static func misfiledDraft() -> RecipeImportDraft {
        .mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 700, unit: "g"),
                ImportedIngredient(name: "Lavender Essential Oil", amount: 10, unit: "g")
            ],
            additives: [ImportedIngredient(name: "Distilled Water", amount: 300, unit: "g")]
        )
    }

    private static let boraxText = "KOH liquid soap. Coconut Oil 40%, Olive Oil 60%. Borax 25 g to neutralise."

    private static func boraxDraft() -> RecipeImportDraft {
        .mock(
            oils: [ImportedIngredient(name: "Coconut Oil", amount: 40, unit: "%"),
                   ImportedIngredient(name: "Olive Oil", amount: 60, unit: "%")],
            additives: [ImportedIngredient(name: "Borax", amount: 25, unit: "g")],
            lyeType: "KOH", superFat: nil, waterParts: nil, fragrancePercentage: nil
        )
    }

    // MARK: - Order

    @Test func steps_AreInTheDefinedOrder() {
        #expect(RecipeImportDraftChecker.Step.allCases == [
            .keepingStatedAmounts,
            .movingMisplacedRows,
            .removingDuplicates,
            .droppingSectionHeaders,
            .checkingBatchSize,
            .readingOilAmounts,
            .readingSharesAsPercentages,
            .clearingStaleBatchSize,
            .settingSuperFat,
            .settingWaterParts,
            .settingFragrancePercentage,
            .settingLyeType,
            .settingLyePurity,
            .settingHybridLye,
            .settingFailorNeutralizer
        ])
    }

    // MARK: - Skipping nothing

    @Test(arguments: [
        (hybridDraft(), hybridText),
        (misfiledDraft(), misfiledText),
        (boraxDraft(), boraxText),
        (RecipeImportDraft.mock(superFat: 5), RecipeImportPastes.shoppingList)
    ])
    func checked_SkippingNothing_EqualsTheDefaultCall(draft: RecipeImportDraft, text: String) {
        let skippingNothing = RecipeImportDraftChecker.checked(draft, against: text, skipping: [])

        #expect(skippingNothing == RecipeImportDraftChecker.checked(draft, against: text))
    }

    // MARK: - Skipping one step

    @Test func checked_SkippingOilAmounts_LeavesTheTableUnreadButStillAppliesTheHybridLye() throws {
        let checked = RecipeImportDraftChecker.checked(
            Self.hybridDraft(), against: Self.hybridText, skipping: [.readingOilAmounts]
        )

        #expect(!checked.amountsArePercentages)
        #expect(checked.oils.map(\.amount) == [14, 2, 2, 1])
        #expect(checked.oils.allSatisfy { $0.unit == "g" })
        #expect(checked.kohPercentage != nil)
        #expect(checked.lyeType == nil)
    }

    @Test func checked_NotSkippingOilAmounts_ReadsTheTable() {
        let checked = RecipeImportDraftChecker.checked(Self.hybridDraft(), against: Self.hybridText)

        #expect(checked.amountsArePercentages)
        #expect(checked.oils.map(\.amount) == [73.68, 10.53, 10.53, 5.26])
    }

    @Test func checked_SkippingMovingMisplacedRows_KeepsTheEssentialOilInTheOilsButStillDropsWater() {
        let moved = RecipeImportDraftChecker.checked(Self.misfiledDraft(), against: Self.misfiledText)
        let skipped = RecipeImportDraftChecker.checked(
            Self.misfiledDraft(), against: Self.misfiledText, skipping: [.movingMisplacedRows]
        )

        #expect(moved.oils.map(\.name) == ["Olive Oil"])
        #expect(moved.fragrances.map(\.name) == ["Lavender Essential Oil"])
        #expect(skipped.oils.map(\.name) == ["Olive Oil", "Lavender Essential Oil"])
        #expect(skipped.fragrances.isEmpty)
        #expect(skipped.additives.isEmpty)
    }

    @Test func checked_SkippingFailorNeutralizer_KeepsTheBoraxRowAndSetsNoNeutralizer() {
        let skipped = RecipeImportDraftChecker.checked(
            Self.boraxDraft(), against: Self.boraxText, skipping: [.settingFailorNeutralizer]
        )

        #expect(skipped.cfmNeutralizer == nil)
        #expect(skipped.additives.map(\.name) == ["Borax"])
        #expect(skipped.lyeType == "KOH")
    }
}
