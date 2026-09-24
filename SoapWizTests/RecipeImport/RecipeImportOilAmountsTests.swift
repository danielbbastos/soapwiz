import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// SW-170: a recipe that gives each oil both a share and a weight, which the
/// model read as weights while still calling them percentages.
@Suite("Recipe import oil amounts", .serialized)
@MainActor
struct RecipeImportOilAmountsTests: RecipeImportTestHelpers {

    private let container: ModelContainer
    private let inventory: [Ingredient]

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        let context = container.mainContext
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        context.insert(oils)
        inventory = OilAmountPastes.everydayOils.map { name in
            let oil = Ingredient(name: name, category: oils, unit: "g")
            oil.sapValue = 0.14
            context.insert(oil)
            return oil
        }
    }

    // MARK: - Preferring the stated percentages

    @Test func checked_ModelTookTheWeights_ImportsThePercentages() throws {
        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: OilAmountPastes.percentThenWeight)

        #expect(checked.oils.map(\.amount) == [35, 25, 20, 10, 10])
        #expect(checked.oils.allSatisfy { $0.unit == "%" })
        #expect(checked.amountsArePercentages)
        #expect(try #require(checked.batchSize) == 600)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_WeightWrittenBeforePercentage_ImportsThePercentages() throws {
        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: OilAmountPastes.weightThenPercent)

        #expect(checked.oils.map(\.amount) == [35, 25, 20, 10, 10])
        #expect(checked.amountsArePercentages)
        #expect(try #require(checked.batchSize) == 600)
    }

    @Test func checked_ModelTookThePercentages_KeepsThemAndReadsTheBatchSize() throws {
        let draft = RecipeImportDraft.everyday(amounts: [35, 25, 20, 10, 10], unit: "%", batchSize: nil)

        let checked = RecipeImportDraftChecker.checked(draft, against: OilAmountPastes.percentThenWeight)

        #expect(checked.oils.map(\.amount) == [35, 25, 20, 10, 10])
        #expect(checked.amountsArePercentages)
        #expect(try #require(checked.batchSize) == 600)
    }

    /// Found on device: the description names olive oil before the list does.
    @Test func checked_DescriptionNamesAnOilFirst_ReadsTheIngredientLine() throws {
        let draft = RecipeImportDraft.bastille(amounts: [720, 200, 80], unit: "g")

        let checked = RecipeImportDraftChecker.checked(draft, against: OilAmountPastes.bastille)

        #expect(checked.oils.map(\.amount) == [72, 20, 8])
        #expect(checked.amountsArePercentages)
        #expect(try #require(checked.batchSize) == 1_000)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_PercentagesOnlyReadAsGrams_ImportsThePercentages() {
        let draft = RecipeImportDraft.bastille(amounts: [72, 20, 8], unit: "g")

        let checked = RecipeImportDraftChecker.checked(draft, against: OilAmountPastes.bastillePercentagesOnly)

        #expect(checked.oils.map(\.amount) == [72, 20, 8])
        #expect(checked.oils.allSatisfy { $0.unit == "%" })
        #expect(checked.amountsArePercentages)
        #expect(checked.batchSize == nil)
    }

    @Test func checked_OilWithoutAModelAmount_TakesTheShareOnItsLine() {
        let draft = RecipeImportDraft.bastille(amounts: [720, 0, 80], unit: "g")

        let checked = RecipeImportDraftChecker.checked(draft, against: OilAmountPastes.bastille)

        #expect(checked.oils.map(\.amount) == [72, 20, 8])
        #expect(checked.amountsArePercentages)
    }

    @Test func checked_WeightsInMixedUnits_ImportsThePercentagesWithoutABatchSize() {
        let text = OilAmountPastes.bastille.replacingOccurrences(of: "Castor Oil — 8% (80 g)", with: "Castor Oil — 8% (2.8 oz)")
        let draft = RecipeImportDraft.bastille(amounts: [720, 200, 2.8], unit: "g")

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        #expect(checked.oils.map(\.amount) == [72, 20, 8])
        #expect(checked.amountsArePercentages)
        #expect(checked.batchSize == nil)
    }

    @Test func checked_WeightsOnly_StaysAWeightRecipe() {
        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: OilAmountPastes.weightsOnly)

        #expect(checked.oils.map(\.amount) == [210, 150, 120, 60, 60])
        #expect(!checked.amountsArePercentages)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_OneOilWithoutAPercentage_KeepsTheWeights() {
        let text = OilAmountPastes.percentThenWeight
            .replacingOccurrences(of: "Sweet Almond Oil — 10% (60 g)", with: "Sweet Almond Oil — 60 g")

        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: text)

        #expect(checked.oils.map(\.amount) == [210, 150, 120, 60, 60])
        #expect(!checked.amountsArePercentages)
        #expect(checked.batchUnit == "g")
    }

    @Test func checked_PercentagesNotAWholeBlend_KeepsTheWeights() {
        let text = OilAmountPastes.percentThenWeight
            .replacingOccurrences(of: "Palm Oil — 35% (210 g)", with: "Palm Oil — 55% (210 g)")

        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: text)

        #expect(checked.oils.map(\.amount) == [210, 150, 120, 60, 60])
        #expect(!checked.amountsArePercentages)
    }

    @Test func checked_GroupedCommaDecimalWeights_SumToTheBatchSize() throws {
        let draft = RecipeImportDraft.everyday(amounts: [35, 25, 20, 10, 10], unit: "%", batchSize: nil)
        let text = """
            Everyday Kitchen Bar
            Palm Oil — 35% (1 312,5 g)
            Coconut Oil — 25% (937,5 g)
            Sunflower Oil — 20% (750 g)
            Rice Bran Oil — 10% (375 g)
            Sweet Almond Oil — 10% (375 g)
            """

        let checked = RecipeImportDraftChecker.checked(draft, against: text)

        #expect(checked.oils.map(\.amount) == [35, 25, 20, 10, 10])
        #expect(try #require(checked.batchSize) == 3_750)
    }

    // MARK: - Matching the flag to the units

    @Test func matchingOilUnits_WeightRowsFlaggedAsPercentages_BecomeWeights() {
        let draft = RecipeImportDraft.everyday(amounts: [24, 8, 8, 2, 2], unit: "oz", batchSize: nil)

        let matched = RecipeImportDraftChecker.matchingOilUnits(draft)

        #expect(!matched.amountsArePercentages)
        #expect(matched.batchUnit == "oz")
    }

    @Test func matchingOilUnits_PercentRowsFlaggedAsWeights_BecomePercentages() {
        var draft = RecipeImportDraft.everyday(amounts: [35, 25, 20, 10, 10], unit: "%", batchSize: nil)
        draft.amountsArePercentages = false

        #expect(RecipeImportDraftChecker.matchingOilUnits(draft).amountsArePercentages)
    }

    @Test func matchingOilUnits_MixedOrMissingUnits_KeepTheFlag() {
        var mixed = RecipeImportDraft.everyday(amounts: [35, 25, 20, 10, 10], unit: "%", batchSize: nil)
        mixed.oils[0].unit = "g"
        let missing = RecipeImportDraft.everyday(amounts: [35, 25, 20, 10, 10], unit: nil, batchSize: nil)

        #expect(RecipeImportDraftChecker.matchingOilUnits(mixed).amountsArePercentages)
        #expect(RecipeImportDraftChecker.matchingOilUnits(missing).amountsArePercentages)
    }

    @Test func matchingOilUnits_NoOilAmounts_KeepTheFlag() {
        let draft = RecipeImportDraft.everyday(amounts: [0, 0, 0, 0, 0], unit: "g", batchSize: nil)
        #expect(RecipeImportDraftChecker.matchingOilUnits(draft).amountsArePercentages)
    }

    // MARK: - Review and form agree

    @Test(arguments: [OilAmountPastes.percentThenWeight, OilAmountPastes.weightsOnly])
    func reviewAndForm_AgreeOnTheOilUnitAndAmounts(text: String) {
        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: text)
        let rows = RecipeIngredientReconciler.reconcile(checked, against: inventory)
        let model = RecipeFormViewModel()

        model.applyImport(PreparedRecipeImport(draft: checked, rows: rows))

        #expect(checked.oilAmountUnit == model.weightUnit)
        #expect(checked.oils.map(\.amount) == model.oilDrafts.map(\.amount))
    }

    @Test func applyImport_ReproRecipe_OpensAt100PercentWithA600GramBatch() {
        let checked = RecipeImportDraftChecker.checked(.everydayWeights(), against: OilAmountPastes.percentThenWeight)
        let model = RecipeFormViewModel()

        model.applyImport(PreparedRecipeImport(draft: checked, rows: RecipeIngredientReconciler.reconcile(checked, against: inventory)))

        #expect(model.weightUnitIsPercentage)
        #expect(model.oilDrafts.map(\.amount).reduce(0, +) == 100)
        #expect(model.totalOilWeight == 600)
        #expect(model.oilWeightUnit == "g")
    }

    // MARK: - Review text

    @Test func amountText_OilRowUnitDisagreesWithTheDraft_UsesTheDraftsUnit() {
        let draft = RecipeImportDraft.mock(amountsArePercentages: true)
        let oil = ImportedIngredient(name: "Palm Oil", amount: 35, unit: "g")

        #expect(draft.amountText(for: oil, role: .oil) == "\(PercentageFormatter.string(35))%")
    }

    @Test func amountText_AdditiveKeepsItsOwnUnit() {
        let draft = RecipeImportDraft.mock(amountsArePercentages: true)
        let clay = ImportedIngredient(name: "Clay", amount: 10, unit: "g")

        #expect(draft.amountText(for: clay, role: .additive) == "\(PercentageFormatter.string(10)) g")
    }

    @Test func amountText_NoAmount_ShowsADash() {
        let oil = ImportedIngredient(name: "Palm Oil", amount: 0, unit: nil)
        #expect(RecipeImportDraft.mock().amountText(for: oil, role: .oil) == "—")
    }
}

/// "Everyday Kitchen Bar", pasted on device while finding SW-170. The last
/// line is what sends SoapWiz's own copy to the model rather than
/// `RecipeTextExportReader`.
enum OilAmountPastes {
    static let everydayOils = ["Palm Oil", "Coconut Oil", "Sunflower Oil", "Rice Bran Oil", "Sweet Almond Oil"]

    static let percentThenWeight = """
        Everyday Kitchen Bar

        Oils
        Palm Oil — 35% (210 g)
        Coconut Oil — 25% (150 g)
        Sunflower Oil — 20% (120 g)
        Rice Bran Oil — 10% (60 g)
        Sweet Almond Oil — 10% (60 g)

        NaOH (99% pure) · 5% superfat · water 2:1
        Cure for six weeks.
        """

    static let bastille = """
        Classic Bastille Bar
        A skin-loving bar built on olive oil with a coconut boost for lather. Gentle enough for daily use.

        Oils
        Olive Oil — 72% (720 g)
        Coconut Oil — 20% (200 g)
        Castor Oil — 8% (80 g)

        Fragrances
        Lavender Essential Oil — 3 % of oils (30 g)

        NaOH (99% pure) · 5% superfat · water 1,5:1

        Cure
        """

    static let bastillePercentagesOnly = """
        Classic Bastille Bar
        A skin-loving bar built on olive oil with a coconut boost for lather.

        Oils
        Olive Oil — 72%
        Coconut Oil — 20%
        Castor Oil — 8%

        NaOH (99% pure) · 5% superfat · water 1,5:1
        """

    static let weightThenPercent = """
        Everyday Kitchen Bar
        - 210 g palm oil (35%)
        - 150 g coconut oil (25%)
        - 120 g sunflower oil (20%)
        - 60 g rice bran oil (10%)
        - 60 g sweet almond oil (10%)
        Cure for six weeks.
        """

    static let weightsOnly = """
        Everyday Kitchen Bar
        Palm Oil 210 g
        Coconut Oil 150 g
        Sunflower Oil 120 g
        Rice Bran Oil 60 g
        Sweet Almond Oil 60 g
        Cure for six weeks.
        """
}

extension RecipeImportDraft {
    /// The Everyday Kitchen Bar oils with the given amounts, flagged as
    /// percentages — the flag the model returned on device.
    static func everyday(amounts: [Double], unit: String?, batchSize: Double?) -> RecipeImportDraft {
        .mock(
            name: "Everyday Kitchen Bar",
            oils: zip(OilAmountPastes.everydayOils, amounts).map { ImportedIngredient(name: $0, amount: $1, unit: unit) },
            amountsArePercentages: true,
            batchSize: batchSize,
            batchUnit: nil,
            superFat: nil,
            waterParts: nil,
            fragrancePercentage: nil
        )
    }

    /// The Classic Bastille Bar oils with the given amounts, flagged as
    /// percentages.
    static func bastille(amounts: [Double], unit: String?) -> RecipeImportDraft {
        .mock(
            name: "Classic Bastille Bar",
            oils: zip(["Olive Oil", "Coconut Oil", "Castor Oil"], amounts)
                .map { ImportedIngredient(name: $0, amount: $1, unit: unit) },
            batchSize: nil,
            batchUnit: nil
        )
    }

    /// What the model returned for the repro: the weights, called percentages.
    static func everydayWeights() -> RecipeImportDraft {
        everyday(amounts: [210, 150, 120, 60, 60], unit: "g", batchSize: nil)
    }
}
