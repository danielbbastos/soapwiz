import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – cost breakdown", .serialized)
@MainActor
struct RecipeCostBreakdownTests: RecipeFormTestHelpers {

    @Test func breakdownAndCost_NoIngredients_ReturnsEmptyAndZeroTotal() {
        let model = RecipeFormViewModel()
        let draft = RecipeProductDraft(unitSymbol: "g")

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils.isEmpty)
        #expect(result.additives.isEmpty)
        #expect(result.fragrances.isEmpty)
        #expect(result.lye.isEmpty)
        #expect(result.total == 0)
    }
    @Test func breakdownAndCost_ZeroSize_ReturnsEmpty() {
        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 0

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils.isEmpty)
        #expect(result.total == 0)
    }
    @Test func breakdownAndCost_NoBatches_AmountsComputedCostZero() {
        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils[0].ingredientAmount == 100)
        #expect(result.oils[0].cost == 0)
        #expect(result.total == 0)
    }
    @Test func breakdownAndCost_SingleBatch_ComputesCostCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        // 100g product / 100g batch = full batch. Oil = 100g × €0.02/g = €2.00
        #expect(result.oils[0].ingredientAmount == 100)
        #expect(result.oils[0].cost == 2.0)
        #expect(result.total == 2.0)
    }
    @Test func breakdownAndCost_MultipleBatches_UsesWeightedAverageCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase1 = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase1.ingredient = ingredient
        ctx.insert(purchase1)
        let purchase2 = IngredientPurchase.mock(quantity: 250, totalPrice: 7.5)
        purchase2.ingredient = ingredient
        ctx.insert(purchase2)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        let expected = 100 * (17.5 / 750.0)
        #expect(abs(result.oils[0].cost - expected) < 0.0001)
        #expect(abs(result.total - expected) < 0.0001)
    }
    @Test func breakdownAndCost_MultipleIngredients_SumsTotalCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let purchase1 = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        purchase1.ingredient = ing1
        ctx.insert(purchase1)

        let ing2 = Ingredient(name: "Shea Butter")
        ctx.insert(ing2)
        let purchase2 = IngredientPurchase.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        purchase2.ingredient = ing2
        ctx.insert(purchase2)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 200
        model.addOil(ing1)
        model.addOil(ing2) // each gets 50%
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 200

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils.count == 2)
        #expect(abs(result.total - 5.0) < 0.0001)
    }
    @Test func breakdownAndCost_PartsOfBatch_DividesBatchCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 1000
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: ProductUnit.partsOfBatch.rawValue)
        draft.size = 10

        let result = model.breakdownAndCost(for: draft)

        // 1000g oils × €0.02/g = €20 batch cost. 1/10 = €2.
        #expect(abs(result.total - 2.0) < 0.0001)
    }
    @Test func breakdownAndCost_ExceedingBatchWeight_ClampsAtBatchTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)

        var draft = RecipeProductDraft(unitSymbol: "kg")
        draft.size = 5  // 5000g vs 100g batch

        let result = model.breakdownAndCost(for: draft)

        #expect(result.exceedsBatchWeight == true)
        #expect(abs(result.total - model.batchTotalCost) < 0.0001)
    }
    /// 1000 g of oils at €0.01/g plus 30 g of fragrance at €0.10/g — a 1030 g
    /// batch costing €13. No sap value, so no lye or water enter the weight.
    private func makeModelWithFragrance(ctx: ModelContext) -> RecipeFormViewModel {
        let oil = Ingredient(name: "Coconut Oil")
        ctx.insert(oil)
        let oilPurchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)
        oilPurchase.ingredient = oil
        ctx.insert(oilPurchase)

        let fragrance = Ingredient(name: "Lavender EO")
        ctx.insert(fragrance)
        let fragrancePurchase = IngredientPurchase.mock(quantity: 100, totalPrice: 10.0)
        fragrancePurchase.ingredient = fragrance
        ctx.insert(fragrancePurchase)

        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        model.setFragranceUnit(.grams)
        model.addFragrance(fragrance)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 30)
        return model
    }

    @Test func breakdownAndCost_FixedSize_CountsFragranceInDenominator() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithFragrance(ctx: ctx)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 103

        let result = model.breakdownAndCost(for: draft)

        // 103 g of a 1030 g batch is 10%, not the 10.3% an oils+lye+water
        // denominator would give. €13 batch × 0.1 = €1.30.
        #expect(abs(model.batchTotalCost - 13) < 1e-6)
        #expect(abs(result.total - 1.30) < 1e-6)
        #expect(abs(result.oils[0].ingredientAmount - 100) < 1e-6)
        #expect(result.exceedsBatchWeight == false)
    }
    @Test func breakdownAndCost_FixedSize_ProductCostsDoNotExceedBatchTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithFragrance(ctx: ctx)
        // Two differently sized bars that between them are exactly the 1030 g
        // batch, so their costs must sum to exactly the batch cost — never more,
        // which is what the old denominator produced (13,39 € against a 13 €
        // batch). Sizes differ so the sum is a real sum, not one value scaled.
        var small = RecipeProductDraft(unitSymbol: "g")
        small.size = 500
        var large = RecipeProductDraft(unitSymbol: "g")
        large.size = 530

        let smallCost = model.breakdownAndCost(for: small).total
        let largeCost = model.breakdownAndCost(for: large).total
        let summed = smallCost + largeCost

        #expect(smallCost < largeCost)
        #expect(abs(summed - model.batchTotalCost) < 1e-6)
    }
    @Test func init_AddsDefaultProductOnePartOfBatch() {
        let model = RecipeFormViewModel()
        #expect(model.productDrafts.count == 1)
        #expect(model.productDrafts[0].size == 1)
        #expect(model.productDrafts[0].unitSymbol == ProductUnit.partsOfBatch.rawValue)
    }
    @Test func batchTotalCost_IncludesAllCategories() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        ctx.insert(oil)
        let oilPurchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)
        oilPurchase.ingredient = oil
        ctx.insert(oilPurchase)
        let lye = Ingredient(name: "Sodium Hydroxide")
        ctx.insert(lye)
        let lyePurchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 8.0)
        lyePurchase.ingredient = lye
        ctx.insert(lyePurchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 1000
        model.lyePurity = 100
        model.superFat = 0
        model.addOil(oil)
        model.lyeIngredient = lye

        // Oils: 1000g × €0.01 = €10
        // Lye: 1000 × 0.2 × 1 / 1 = 200g × €0.008 = €1.60
        #expect(abs(model.batchTotalCost - 11.60) < 0.001)
    }
    @Test func resolveDefaultLyeIngredient_PicksSodiumHydroxide() {
        let lyeCategory = IngredientCategory(name: IngredientCategory.Name.lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide (Lye)", category: lyeCategory, unit: "g")
        let other = Ingredient(name: "Other Lye", category: lyeCategory, unit: "g")

        let model = RecipeFormViewModel()
        model.resolveDefaultLyeIngredient(from: [other, naoh])

        #expect(model.lyeIngredient?.name == "Sodium Hydroxide (Lye)")
    }
    @Test func resolveDefaultLyeIngredient_DoesNotOverrideExisting() {
        let lyeCategory = IngredientCategory(name: IngredientCategory.Name.lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide", category: lyeCategory, unit: "g")
        let custom = Ingredient(name: "Custom Lye", category: lyeCategory, unit: "g")

        let model = RecipeFormViewModel()
        model.lyeIngredient = custom
        model.resolveDefaultLyeIngredient(from: [naoh, custom])

        #expect(model.lyeIngredient === custom)
    }
}
