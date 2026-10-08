import Testing
import Foundation
@testable import SoapWiz

/// The figures the recipe form's ingredient sheets read from the view model:
/// whether the percentage total is complete, and each oil's weight in the batch.
@Suite("Recipe form ingredient sheets")
@MainActor
struct RecipeFormIngredientSheetTests: RecipeFormTestHelpers {

    /// 1 000 g of oils on the percentage scale, one row per amount. The amounts
    /// are set once every row is in, since each add redistributes the scale.
    private func makePercentageModel(amounts: [Double]) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.lyePurity = 100
        model.superFat = 0
        for index in amounts.indices {
            let oil = Ingredient(name: "Oil \(index)")
            oil.sapValue = 0.2
            model.addOil(oil)
        }
        for (index, amount) in amounts.enumerated() {
            model.oilDrafts[index].amount = amount
        }
        return model
    }

    // MARK: - isPercentageTotalComplete

    @Test func isPercentageTotalComplete_AtExactly100_IsTrue() {
        let model = makePercentageModel(amounts: [60, 40])
        #expect(model.isPercentageTotalComplete)
    }

    @Test func isPercentageTotalComplete_WithinATenth_IsTrue() {
        let model = makePercentageModel(amounts: [60, 40.05])
        #expect(model.isPercentageTotalComplete)
    }

    @Test(arguments: [99.8, 90.0, 100.2])
    func isPercentageTotalComplete_MoreThanATenthOff_IsFalse(total: Double) {
        let model = makePercentageModel(amounts: [total])
        #expect(!model.isPercentageTotalComplete)
    }

    @Test func isPercentageTotalComplete_NoOils_IsFalse() {
        let model = makePercentageModel(amounts: [])
        #expect(!model.isPercentageTotalComplete)
    }

    // MARK: - canSave and the percentage total

    @Test func canSave_PercentageTotalOff_IsFalse() {
        let model = makePercentageModel(amounts: [60, 30])
        model.name = "Bastille"
        #expect(model.percentageTotalBlocksSave)
        #expect(!model.canSave)
    }

    @Test func canSave_PercentageTotalComplete_IsTrue() {
        let model = makePercentageModel(amounts: [60, 40])
        model.name = "Bastille"
        #expect(!model.percentageTotalBlocksSave)
        #expect(model.canSave)
    }

    @Test func canSave_PercentageModeWithNoOils_IsTrue() {
        let model = makePercentageModel(amounts: [])
        model.name = "Draft"
        #expect(model.canSave)
    }

    @Test func canSave_AbsoluteModeAmountsNotTotalling100_IsTrue() {
        let model = makePercentageModel(amounts: [300, 150])
        model.weightUnit = "g"
        model.name = "Bastille"
        #expect(model.canSave)
    }

    @Test func canSave_PercentageTotalOffButNoName_IsFalse() {
        let model = makePercentageModel(amounts: [60, 40])
        #expect(!model.canSave)
    }

    @Test func canSave_NonSoapPercentageAdditive_CountsTowardTheTotal() throws {
        let model = makePercentageModel(amounts: [100])
        model.isNonSoapProduct = true
        model.name = "Balm"
        model.addAdditive(Ingredient(name: "Beeswax"))
        let additive = try #require(model.additiveDrafts.first)
        model.updateAdditive(id: additive.id, amount: 10, unit: RecipeUnitOptions.percentOfTotal)
        #expect(model.canSave)

        model.oilDrafts[0].amount = 80
        #expect(!model.canSave)
    }

    @Test func canSave_SavedRecipeAlreadyOff100AndUnedited_IsTrue() {
        let model = makePercentageModel(amounts: [60, 30])
        model.name = "Bastille"
        model.captureSnapshot()

        model.name = "Bastille Bar"

        #expect(!model.percentageTotalBlocksSave)
        #expect(model.canSave)
    }

    @Test func canSave_SavedRecipeAlreadyOff100AfterARowEdit_IsFalse() {
        let model = makePercentageModel(amounts: [60, 30])
        model.name = "Bastille"
        model.captureSnapshot()

        model.oilDrafts[1].amount = 35

        #expect(!model.canSave)
    }

    @Test func canSave_SwitchedToPercentageAfterLoad_IsHeldToTheRule() {
        let model = makePercentageModel(amounts: [60, 30])
        model.weightUnit = "g"
        model.name = "Bastille"
        model.captureSnapshot()

        model.weightUnit = "%"

        #expect(!model.canSave)
    }

    // MARK: - oilBatchWeightsByDraftID

    @Test func oilBatchWeights_PercentageMode_ResolveAgainstTheOilWeight() throws {
        let model = makePercentageModel(amounts: [60, 40])
        let weights = model.oilBatchWeightsByDraftID

        let first = try #require(weights[model.oilDrafts[0].id])
        let second = try #require(weights[model.oilDrafts[1].id])
        #expect(abs(first - 600) < 0.001)
        #expect(abs(second - 400) < 0.001)
    }

    @Test func oilBatchWeights_AbsoluteMode_AreTheEnteredAmounts() throws {
        let model = makeModelWithOils()
        model.weightUnit = "g"
        model.oilDrafts[0].amount = 750
        let weights = model.oilBatchWeightsByDraftID

        let weight = try #require(weights[model.oilDrafts[0].id])
        #expect(weights.count == 1)
        #expect(abs(weight - 750) < 0.001)
    }

    @Test func oilBatchWeights_NoOils_IsEmpty() {
        let model = makePercentageModel(amounts: [])
        #expect(model.oilBatchWeightsByDraftID.isEmpty)
    }

    @Test func oilBatchWeights_UnresolvableLye_IsEmpty() {
        let model = makePercentageModel(amounts: [100])
        model.lyePurity = 0
        #expect(model.oilBatchWeightsByDraftID.isEmpty)
    }
}
