import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – extras & fragrance", .serialized)
@MainActor
struct RecipeExtrasTests: RecipeFormTestHelpers {

    @Test func extraIngredientData_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        #expect(model.extraIngredientData == nil)
    }
    @Test func extraIngredientData_IncompleteOilWeight_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 0

        #expect(model.extraIngredientData == nil)
    }
    @Test func extraIngredientData_SectionA_HasTwoRows() throws {
        let model = makeModelWithOils()
        let data = try #require(model.extraIngredientData)
        #expect(data.sectionA.count == 2)
    }
    @Test func extraIngredientData_SectionB_HasSevenRows() throws {
        let model = makeModelWithOils()
        let data = try #require(model.extraIngredientData)
        #expect(data.sectionB.count == 7)
    }
    @Test func extraIngredientData_SodiumLactate_ComputesThreePercentages() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionA[0]
        #expect(row.label == "Sodium Lactate (60%)")
        #expect(abs(row.val1 - 10) < 0.001)
        #expect(abs(row.val2 - 20) < 0.001)
        #expect(abs(row.val3 - 30) < 0.001)
        #expect(row.naohLye == nil)
    }
    @Test func extraIngredientData_CitricAcid_ComputesThreePercentages() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionA[1]
        #expect(row.label == "Citric Acid Powder")
        #expect(abs(row.val1 - 10) < 0.001)
        #expect(abs(row.val2 - 20) < 0.001)
        #expect(abs(row.val3 - 30) < 0.001)
    }
    @Test func extraIngredientData_CitricAcid_NaOHSubRow_IsAcidTimesFactorOverPurity() throws {
        // Single NaOH at 100% purity: extra NaOH = acid × 0.625 (the actual lye,
        // no water), matching LyeCalc's "Extra Lye to Neutralize".
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let naoh = try #require(data.sectionA[1].naohLye)
        // citric_1pct = 10 → 10 * 0.625 = 6.25
        #expect(abs(naoh.val1 - 6.25) < 0.001)
        #expect(abs(naoh.val2 - 12.5) < 0.001)
        #expect(abs(naoh.val3 - 18.75) < 0.001)
    }
    @Test func extraIngredientData_CitricAcid_NaOHSubRow_IndependentOfWaterAndScalesWithPurity() throws {
        // The extra lye is the lye itself (no water), so the water:lye ratio
        // doesn't change it.
        let modelA = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let modelB = makeModelWithOils(oils: 1000, waterParts: 1.0)
        let dataA = try #require(modelA.extraIngredientData)
        let dataB = try #require(modelB.extraIngredientData)
        let naohA = try #require(dataA.sectionA[1].naohLye)
        let naohB = try #require(dataB.sectionA[1].naohLye)
        #expect(abs(naohA.val1 - naohB.val1) < 0.001)

        // Lower purity needs more lye.
        let lowPurity = makeModelWithOils(oils: 1000)
        lowPurity.lyePurity = 90
        let lowData = try #require(lowPurity.extraIngredientData)
        let naohLow = try #require(lowData.sectionA[1].naohLye)
        #expect(naohLow.val1 > naohA.val1)
    }
    @Test func extraIngredientData_EOFO_ComputesCorrectly() throws {
        let model = makeModelWithOils(oils: 1000)
        // fragrancePercentage defaults to 3 → 1000 × 0.03 = 30
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[0]
        #expect(row.label == "EO / Fragrance Oil")
        #expect(abs(row.minValue - 30) < 0.001)
        #expect(row.maxValue == nil)
        #expect(row.naohLye == nil)
    }
    @Test func extraIngredientData_AscorbicAcid_ComputesValueAndNaOH() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[1]
        #expect(row.label == "Ascorbic Acid")
        #expect(abs(row.minValue - 10) < 0.001)
        #expect(row.maxValue == nil)
        // naoh = 10 * 0.2020 = 2.02 (100% purity, single NaOH)
        let naoh = try #require(row.naohLye)
        #expect(abs(naoh - 2.02) < 0.001)
    }
    @Test func extraIngredientData_LacticAcid_ComputesValueAndNaOH() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[2]
        #expect(row.label == "Lactic Acid")
        #expect(abs(row.minValue - 7.5) < 0.001)
        #expect(row.maxValue == nil)
        // naoh = 7.5 * 0.5920 = 4.44 (100% purity, single NaOH)
        let naoh = try #require(row.naohLye)
        #expect(abs(naoh - 4.44) < 0.001)
    }
    @Test func extraIngredientData_TetrasodiumEDTA_UsesBatchTotal() throws {
        // oils = 1000, lye = 200, water = 300 → batchTotal = 1500
        let model = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[3]
        #expect(row.label == "Tetrasodium EDTA")
        // 1500 * 0.005 = 7.5
        #expect(abs(row.minValue - 7.5) < 0.001)
        #expect(row.maxValue == nil)
        #expect(row.naohLye == nil)
    }
    @Test func extraIngredientData_SodiumCitrate_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[4]
        #expect(row.label == "Sodium Citrate")
        #expect(abs(row.minValue - 13) < 0.001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 39) < 0.001)
    }
    @Test func extraIngredientData_PotassiumCitrate_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[5]
        #expect(row.label == "Potassium Citrate")
        #expect(abs(row.minValue - 16) < 0.001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 48) < 0.001)
    }
    @Test func extraIngredientData_ROE_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[6]
        #expect(row.label == "Rosemary Oleoresin (ROE)")
        #expect(abs(row.minValue - 0.4) < 0.0001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 0.5) < 0.0001)
    }
    @Test func extraIngredientData_ScalesWithOilWeight() throws {
        let model2000 = makeModelWithOils(oils: 2000)
        let model1000 = makeModelWithOils(oils: 1000)
        let data2000 = try #require(model2000.extraIngredientData)
        let data1000 = try #require(model1000.extraIngredientData)
        // All values should double when oil weight doubles
        #expect(abs(data2000.sectionA[0].val1 - data1000.sectionA[0].val1 * 2) < 0.001)
        #expect(abs(data2000.sectionB[0].minValue - data1000.sectionB[0].minValue * 2) < 0.001)
    }
    @Test func matchedExtraIngredient_LabelContainsIngredientName() {
        let model = RecipeFormViewModel()
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        let match = model.matchedExtraIngredient(label: "Citric Acid Powder", in: [citric])
        #expect(match === citric)
    }
    @Test func matchedExtraIngredient_IngredientNameContainsLabel() {
        let model = RecipeFormViewModel()
        let ascorbic = Ingredient(name: "Ascorbic Acid (Vitamin C)", unit: "g")
        let match = model.matchedExtraIngredient(label: "Ascorbic Acid", in: [ascorbic])
        #expect(match === ascorbic)
    }
    @Test func matchedExtraIngredient_NoMatch_ReturnsNil() {
        let model = RecipeFormViewModel()
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        #expect(model.matchedExtraIngredient(label: "EO / Fragrance Oil", in: [citric]) == nil)
    }
    @Test func matchedExtraIngredient_EmptyInventory_ReturnsNil() {
        let model = RecipeFormViewModel()
        #expect(model.matchedExtraIngredient(label: "Citric Acid Powder", in: []) == nil)
    }
    @Test func toggleExtra_AddsAdditiveDraftInBatchUnit() {
        let model = makeNaohModel()
        let citric = Ingredient(name: "Citric Acid", unit: "g")

        model.toggleExtra(citric, amount: 10)

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts[0].ingredient === citric)
        #expect(model.additiveDrafts[0].amount == 10)
        #expect(model.additiveDrafts[0].unit == model.displayWeightUnit)
    }
    @Test func toggleExtra_Twice_RemovesDraft() {
        let model = makeNaohModel()
        let citric = Ingredient(name: "Citric Acid", unit: "g")

        model.toggleExtra(citric, amount: 10)
        model.toggleExtra(citric, amount: 10)

        #expect(model.additiveDrafts.isEmpty)
    }
    @Test func isExtraAdded_ManuallyAddedAdditive_IsTrue() {
        let model = RecipeFormViewModel()
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        model.addAdditive(citric)
        #expect(model.isExtraAdded(citric) == true)
    }
    @Test func isExtraAdded_NotAdded_IsFalse() {
        let model = RecipeFormViewModel()
        #expect(model.isExtraAdded(Ingredient(name: "Citric Acid", unit: "g")) == false)
    }
    @Test func fragranceTarget_MassUnit_ShowsTargetTotalAndPercentage() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .grams)
        let target = try #require(model.fragranceTarget)
        #expect(target.percentage == 3)
        // 3% of 1000 g oils = 30 g
        #expect(target.text.contains("30"))
        #expect(target.text.contains("g"))
        #expect(target.text.contains("3%"))
    }
    @Test func fragranceTarget_OzUnit_ConvertsTargetToThatUnit() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .ounces)
        let target = try #require(model.fragranceTarget)
        #expect(target.text.contains("oz"))
        #expect(target.text.contains("3%"))
    }
    @Test func fragranceTarget_EnteredOverTarget_SetsFlag() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .grams)
        // Target is 3% of 1000 g = 30 g; enter 60 g.
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 60)
        let target = try #require(model.fragranceTarget)
        #expect(target.isOverTarget == true)
    }
    @Test func fragranceTarget_EnteredUnderTarget_FlagFalse() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .grams)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 20)
        let target = try #require(model.fragranceTarget)
        #expect(target.isOverTarget == false)
    }
    @Test func fragranceTarget_PercentageUnit_ReturnsNil() {
        // Default unit in percentage mode is "% of oils".
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceTarget == nil)
    }
    @Test func fragranceTarget_PercentOfFragrances_ShowsLoadAndNeverOverTarget() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .percentOfFragrances)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 250)
        let target = try #require(model.fragranceTarget)
        // The load is 3% of 1000 g oils = 30 g; shares are normalised, so even
        // a share sum far past 100 can't exceed it.
        #expect(target.percentage == 3)
        #expect(target.text.contains("30"))
        #expect(target.text.contains("3%"))
        #expect(target.isOverTarget == false)
    }
    @Test func fragranceTarget_NoFragrances_ReturnsNil() {
        let model = makeModelWithOils()
        #expect(model.fragranceTarget == nil)
    }
    @Test func fragranceTarget_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.setFragranceUnit(.grams)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceTarget == nil)
    }
}
