import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – lye calculation", .serialized)
@MainActor
struct RecipeLyeCalculationTests: RecipeFormTestHelpers {

    @Test func oilAmountCalculations_ZeroPurity_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.lyePurity = 0

        #expect(model.oilAmountCalculations == nil)
    }
    @Test func oilAmountCalculations_PurityAbove100_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.lyePurity = 101

        #expect(model.oilAmountCalculations == nil)
    }
    @Test func breakdownAndCost_DirectWeightMode_UsesOilShareNotPercentage() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let purchase1 = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        purchase1.ingredient = ing1
        ctx.insert(purchase1)

        let ing2 = Ingredient(name: "Olive Oil")
        ctx.insert(ing2)
        let purchase2 = IngredientPurchase.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        purchase2.ingredient = ing2
        ctx.insert(purchase2)

        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(ing1)
        model.oilDrafts[0].amount = 300  // 300g
        model.addOil(ing2)
        model.oilDrafts[1].amount = 100  // 100g — batch total 400g

        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 200

        let result = model.breakdownAndCost(for: draft)

        // 200g / 400g batch = 0.5 share
        // ing1: 300 × 0.5 = 150g × €0.01 = €1.50
        // ing2: 100 × 0.5 =  50g × €0.04 = €2.00
        #expect(abs(result.oils[0].ingredientAmount - 150) < 0.001)
        #expect(abs(result.oils[1].ingredientAmount - 50) < 0.001)
        #expect(abs(result.total - 3.5) < 0.001)
    }
    @Test func displayWeightUnit_PercentageMode_UsesOilWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        #expect(model.displayWeightUnit == "kg")
    }
    @Test func displayWeightUnit_DirectWeightMode_UsesWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        #expect(model.displayWeightUnit == "oz")
    }
    @Test func oilAmountCalculations_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        #expect(model.oilAmountCalculations == nil)
    }
    @Test func oilAmountCalculations_PercentageMode_ZeroTotalWeight_ReturnsNil() {
        let model = RecipeFormViewModel()
        // weightUnit defaults to "%"
        model.totalOilWeight = 0
        model.addOil(Ingredient(name: "Coconut Oil"))
        #expect(model.oilAmountCalculations == nil)
    }
    @Test func oilAmountCalculations_PercentageMode_SingleOil_ComputesWeightAndLye() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)   // gets 100%
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0

        let calcs = try #require(model.oilAmountCalculations)
        #expect(calcs.count == 1)
        #expect(calcs[0].weight == 1000)
        // lye = 1000 * 0.2 * (1 - 0/100) / (100/100) = 200
        #expect(abs(calcs[0].lye - 200) < 0.001)
    }
    @Test func oilAmountCalculations_PercentageMode_NoSapValue_LyeIsZero() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Unknown Oil")
        oil.sapValue = nil
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 99
        model.superFat = 5

        let calcs = model.oilAmountCalculations
        #expect(calcs != nil)
        #expect(calcs?[0].lye == 0)
    }
    @Test func oilAmountCalculations_PercentageMode_KgUnit_NoConversion() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1
        model.oilWeightUnit = "kg"
        model.lyePurity = 100
        model.superFat = 0

        let calcs = model.oilAmountCalculations
        // unit is just a label — value stays as 1 (kg)
        #expect(abs((calcs?[0].weight ?? -1) - 1.0) < 0.001)
    }
    @Test func oilAmountCalculations_DirectWeightMode_ComputesWeightAndLye() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.weightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = 500
        model.lyePurity = 100
        model.superFat = 0

        let calcs = model.oilAmountCalculations
        #expect(calcs?.count == 1)
        #expect(abs((calcs?[0].weight ?? -1) - 500) < 0.001)
        // lye = 500 * 0.2 * 1 / 1 = 100
        #expect(abs((calcs?[0].lye ?? -1) - 100) < 0.001)
    }
    @Test func oilAmountCalculations_DirectWeightMode_ZeroAmount_ReturnsNil() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(Ingredient(name: "Coconut Oil"))
        // amount stays 0 — treated as zero
        #expect(model.oilAmountCalculations == nil)
    }
    @Test func calculatedLyeAmount_SumsLyeFromAllOils() {
        let model = RecipeFormViewModel()
        let oilA = Ingredient(name: "A")
        oilA.sapValue = 0.2
        let oilB = Ingredient(name: "B")
        oilB.sapValue = 0.1
        model.weightUnit = "g"
        model.addOil(oilA)
        model.oilDrafts[0].amount = 500
        model.addOil(oilB)
        model.oilDrafts[1].amount = 500
        model.lyePurity = 100
        model.superFat = 0

        // lye_A = 500 * 0.2 = 100, lye_B = 500 * 0.1 = 50 → total = 150
        let lye = model.calculatedLyeAmount
        #expect(abs((lye ?? -1) - 150) < 0.001)
    }
    @Test func calculatedLyeAmount_NilWhenNoCalculations() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedLyeAmount == nil)
    }
    @Test func calculatedWaterAmount_CorrectRatio() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.weightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = 500
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = 2

        // lye = 100, water = 100 * 2 = 200
        let water = model.calculatedWaterAmount
        #expect(abs((water ?? -1) - 200) < 0.001)
    }
    @Test func calculatedWaterAmount_NilWhenNoCalculations() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedWaterAmount == nil)
    }
    @Test func calculatedAmountRows_NilWhenNoOils() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedAmountRows == nil)
    }
    @Test func calculatedAmountRows_SingleOil_ReturnsFiveRows() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        // waterParts = 1.5 (default)

        let rows = model.calculatedAmountRows
        // 1 oil row + oils total + NaOH + Water + Batch total = 5
        #expect(rows?.count == 5)
    }
    @Test func calculatedAmountRows_BatchTotalIsSumOfAll() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = 1.5

        let rows = try #require(model.calculatedAmountRows)
        // oil=1000, lye=200, water=300 → batch=1500
        let batchRow = try #require(rows.last)
        #expect(batchRow.isSummary == true)
        #expect(abs(batchRow.weight - 1500) < 0.1)
        #expect(abs(batchRow.pct - 100) < 0.001)
    }
    @Test func load_PopulatesFragranceDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lavender EO", unit: "ml")
        ctx.insert(ingredient)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .fragrance)
        recipeIngredient.additiveAmount = 10
        recipeIngredient.additiveUnit = "ml"
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.fragranceDrafts[0].ingredient.name == "Lavender EO")
        #expect(model.fragranceDrafts[0].amount == 10)
        #expect(model.fragranceDrafts[0].unit == "ml")
    }
    @Test func calculatedLyeAmount_CitricAcidAdditive_AddsNeutralizationLye() throws {
        let model = makeNaohModel()
        model.toggleExtra(Ingredient(name: "Citric Acid", unit: "g"), amount: 10)

        // 200 base + 10 g × 0.625 = 206.25
        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 206.25) < 1e-9)
    }
    @Test func calculatedLyeAmount_AscorbicAcid_MatchesExtrasTableFigure() throws {
        let model = makeNaohModel()
        model.toggleExtra(Ingredient(name: "Ascorbic Acid", unit: "g"), amount: 5)

        // 200 base + 5 g × 0.2020 = 201.01; with waterParts 1.5 the combined
        // lye+water increase (1.01 + 1.515) equals the extras table's 2.525 g
        // lye-solution figure.
        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 201.01) < 1e-9)
        let water = try #require(model.calculatedWaterAmount)
        #expect(abs(water - 201.01 * 1.5) < 1e-9)
    }
    @Test func calculatedLyeAmount_LacticAcidVolumeDraft_ConvertsViaDensity() throws {
        let model = makeNaohModel()
        let lactic = Ingredient(name: "Lactic Acid", unit: "ml")
        lactic.density = 1.2
        model.toggleExtra(lactic, amount: 0)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 10, unit: "ml")

        // 10 ml × 1.2 g/ml = 12 g × 0.5920 = 7.104 extra
        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 207.104) < 1e-9)
    }
    @Test func calculatedLyeAmount_PartialAcidName_StillCompensates() throws {
        // "Citric" matches the extras row via bidirectional containment, so the
        // same rule must drive the factor lookup — a toggled match always
        // carries its lye compensation.
        let model = makeNaohModel()
        model.toggleExtra(Ingredient(name: "Citric", unit: "g"), amount: 10)

        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 206.25) < 1e-9)
    }
    @Test func calculatedLyeAmount_KOHRecipe_UsesKOHSapAndCompensatesWithKOH() throws {
        let model = makeNaohModel()        // oil sapValue 0.2, purity 100
        model.oilDrafts[0].ingredient.kohSapValue = 0.28
        model.lyeType = "KOH"
        model.toggleExtra(Ingredient(name: "Citric Acid", unit: "g"), amount: 10)

        // Base KOH lye = 1000 × 0.28 = 280; acid KOH = 10 × 0.625 × molar ratio.
        let acidKOH = 10 * 0.625 * LyeCalculator.kohPerNaOHMass
        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - (280 + acidKOH)) < 1e-9)
        // It is all KOH — no NaOH.
        #expect(model.calculatedNaOHLyeAmount == 0)
        #expect(abs((model.calculatedKOHLyeAmount ?? 0) - (280 + acidKOH)) < 1e-9)
    }
    @Test func calculatedLyeAmount_LowerPurity_ScalesCompensation() throws {
        // Purity 50%: base 400, citric compensation 10 × 0.625 / 0.5 = 12.5
        let model = makeNaohModel(purity: 50)
        model.toggleExtra(Ingredient(name: "Citric Acid", unit: "g"), amount: 10)

        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 412.5) < 1e-9)
    }
    @Test func calculatedLyeAmount_PercentUnitAcid_NoCompensationNoRecursion() throws {
        let model = makeNaohModel()
        model.addAdditive(Ingredient(name: "Citric Acid", unit: "g"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5, unit: "% of batch")

        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 200) < 1e-9)
    }
    @Test func calculatedLyeAmount_NonAcidAdditive_NoCompensation() throws {
        let model = makeNaohModel()
        model.toggleExtra(Ingredient(name: "Sea Salt", unit: "g"), amount: 10)

        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 200) < 1e-9)
    }
}
