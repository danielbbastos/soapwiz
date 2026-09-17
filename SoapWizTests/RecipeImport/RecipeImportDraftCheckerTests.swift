import Testing
import Foundation
@testable import SoapWiz

/// Each case replays a recipe pasted on device while testing SW-147, paired
/// with what the model actually returned for it.
@Suite("Recipe import draft checker")
struct RecipeImportDraftCheckerTests {

    // MARK: - Invented amounts

    @Test func checked_ShoppingListWithoutAmounts_ZeroesInventedAmounts() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "olive oil", amount: 200, unit: "g"),
                ImportedIngredient(name: "coconut oil", amount: 100, unit: "g")
            ],
            additives: [ImportedIngredient(name: "clay", amount: 10, unit: "g")],
            fragrances: [ImportedIngredient(name: "lavender", amount: 10, unit: "g")],
            batchSize: 300,
            lyeType: nil,
            superFat: nil,
            waterParts: nil,
            fragrancePercentage: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.shoppingList)

        #expect((checked.oils + checked.additives + checked.fragrances).allSatisfy { $0.amount == 0 })
        #expect(checked.oils.map(\.name) == ["olive oil", "coconut oil"])
        #expect(checked.batchSize == nil)
    }

    @Test func checked_AmountsWrittenInText_AreKept() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 45, unit: "%")],
            additives: [ImportedIngredient(name: "Sodium Lactate", amount: 15, unit: "g")],
            batchSize: 800
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.headers)

        #expect(checked.oils.first?.amount == 45)
        #expect(checked.additives.first?.amount == 15)
        #expect(checked.batchSize == 800)
    }

    // MARK: - Rows that aren't ingredients

    @Test func checked_LyeAndWaterRows_AreDroppedAndSetTheLyeType() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "olive oil (pomace is fine)", amount: 700, unit: "g"),
                ImportedIngredient(name: "sodium hydroxide", amount: 131, unit: "g")
            ],
            additives: [ImportedIngredient(name: "distilled water", amount: 300, unit: "g")],
            amountsArePercentages: false,
            lyeType: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.blogPost)

        #expect(checked.oils.map(\.name) == ["olive oil (pomace is fine)"])
        #expect(checked.additives.isEmpty)
        #expect(checked.lyeType == "NaOH")
    }

    @Test func checked_LyeRowNamingItsKind_SetsTheLyeTypeWhenTheTextCannot() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Coconut Oil", amount: 300, unit: "g")],
            additives: [ImportedIngredient(name: "KOH", amount: 211, unit: "g")],
            lyeType: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Coconut Oil 300 g\nLye 211 g")

        #expect(checked.additives.isEmpty)
        #expect(checked.lyeType == "KOH")
    }

    @Test func checked_SettingReportedAsAnIngredient_IsDropped() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 600, unit: "g"),
                ImportedIngredient(name: "Oil", amount: 100, unit: "g")
            ],
            additives: [
                ImportedIngredient(name: "Sugar solution", amount: 30, unit: "g"),
                ImportedIngredient(name: "Superfat 3%", amount: 3, unit: "%")
            ],
            superFat: nil
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.liquidSoap)

        #expect(checked.oils.map(\.name) == ["Olive Oil", "Oil"])
        #expect(checked.additives.map(\.name) == ["Sugar solution"])
        #expect(checked.superFat == 3)
        #expect(checked.lyeType == "KOH")
    }

    @Test func checked_RoseWater_IsKept() {
        let draft = RecipeImportDraft.mock(additives: [ImportedIngredient(name: "Rose Water", amount: 50, unit: "g")])

        let checked = RecipeImportDraftChecker.checked(draft, against: "Rose Water 50 g")

        #expect(checked.additives.map(\.name) == ["Rose Water"])
    }

    @Test func checked_SectionHeaders_AreStillDropped() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Oils:", amount: 0, unit: nil),
                ImportedIngredient(name: "Olive Oil", amount: 45, unit: "%")
            ]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.headers)

        #expect(checked.oils.map(\.name) == ["Olive Oil"])
    }

    /// On device the model gave the header "Fragrance" an amount the text
    /// never states. Once that amount is zeroed it is a bare header again.
    @Test func checked_SectionHeaderWithInventedAmount_IsDropped() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive oil", amount: 0, unit: nil)],
            fragrances: [
                ImportedIngredient(name: "Fragrance", amount: 10, unit: "g"),
                ImportedIngredient(name: "Fragrance", amount: 5, unit: "g"),
                ImportedIngredient(name: "Lavender", amount: 0, unit: nil)
            ]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.shoppingList)

        #expect(checked.fragrances.map(\.name) == ["Lavender"])
    }

    // MARK: - Settings

    @Test func checked_SuperfatTakenFromTheLyeWeight_IsReplacedByTheStatedValue() {
        let draft = RecipeImportDraft.mock(lyeType: "NaOH", superFat: 4.5, waterParts: nil)

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.beerParagraph)

        #expect(checked.superFat == 6)
    }

    @Test func checked_FragranceLoadTakenFromAnAmount_IsCleared() {
        let draft = RecipeImportDraft.mock(fragrancePercentage: 15)

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.table)

        #expect(checked.fragrancePercentage == nil)
        #expect(checked.superFat == 5)
        #expect(checked.waterParts.map { abs($0 - 2.2) < 0.0001 } == true)
    }

    @Test func checked_FragranceLoadBesideAnEssentialOil_IsKept() {
        let draft = RecipeImportDraft.mock(fragrancePercentage: 3)

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.headers)

        #expect(checked.fragrancePercentage == 3)
    }

    @Test func checked_SettingNearItsKeywordButUnparsed_IsKept() {
        let draft = RecipeImportDraft.mock(superFat: 5)

        let checked = RecipeImportDraftChecker.checked(draft, against: "Superfat (lye discount) around 5 for this one")

        #expect(checked.superFat == 5)
    }

    @Test func checked_SettingsAbsentFromText_AreCleared() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: 5, waterParts: 2, fragrancePercentage: 3)

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.shoppingList)

        #expect(checked.superFat == nil)
        #expect(checked.waterParts == nil)
        #expect(checked.fragrancePercentage == nil)
        #expect(checked.lyeType == nil)
    }

    @Test func checked_TextNamesOneLye_OverridesTheModel() {
        let draft = RecipeImportDraft.mock(lyeType: "NaOH")

        let checked = RecipeImportDraftChecker.checked(draft, against: RecipeImportPastes.liquidSoap)

        #expect(checked.lyeType == "KOH")
    }

    @Test func checked_TextNamesNoLye_KeepsTheModelsLyeType() {
        let draft = RecipeImportDraft.mock(lyeType: "NaOH")

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 70%\nCoconut Oil 30%")

        #expect(checked.lyeType == "NaOH")
    }

    @Test func checked_EverythingDropped_HasNoIngredient() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Sodium Hydroxide", amount: 131, unit: "g")],
            additives: [ImportedIngredient(name: "Water", amount: 300, unit: "g")]
        )

        let checked = RecipeImportDraftChecker.checked(draft, against: "Sodium Hydroxide 131 g, Water 300 g")

        #expect(!checked.hasAnyIngredient)
    }
}

/// The recipes pasted on device while testing SW-147.
enum RecipeImportPastes {
    static let headers = """
        Lavender Oatmeal Bar

        Oils:
          Olive Oil 45%
          Coconut Oil 25%
        Additives:
          Sodium Lactate 15 g
        Fragrance:
          Lavender Essential Oil 3% of oils

        Lye: NaOH, 5% superfat, water:lye 2:1
        Batch size: 800 g
        """

    static let blogPost = """
        INGREDIENTS
        - 700 g olive oil (pomace is fine)
        - 200 g coconut oil 76°F
        - 131 g sodium hydroxide
        - 300 g distilled water
        """

    static let beerParagraph = """
        Beer bar, 32 oz oils: lard 12 oz, coconut oil 8 oz, olive oil 8 oz, castor 2 oz, cocoa butter 2 oz. \
        Use 4.5 oz lye (NaOH) at 6% superfat and replace the water with 11 oz flat stout. At trace stir in \
        1 tsp honey and 1 oz sweet orange essential oil.
        """

    static let table = """
        Olive Oil           | 40    | 400
        Additives:
        Activated Charcoal  |       | 10
        Fragrances:
        Tea Tree EO         |       | 15
        Peppermint EO       |       | 10
        -----------------------------------------
        Superfat: 5%     Lye: NaOH     Water: 2.2 x lye
        """

    static let liquidSoap = """
        OILS
        Olive Oil — 600 g
        Oil — 100 g   (whatever liquid oil you have left, I used sunflower)

        LYE
        KOH 90% — 211 g

        ADDITIVES
        Sugar solution — 30 g

        Superfat 3%
        """

    static let shoppingList = """
        Soap supplies to buy:

        Oils:
        Olive oil
        Coconut oil

        Fragrance:
        Lavender

        Additives:
        Clay
        """
}
