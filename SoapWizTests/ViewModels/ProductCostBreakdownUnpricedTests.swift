import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("ProductCostBreakdown – unpriced ingredients")
@MainActor
struct ProductCostBreakdownUnpricedTests: RecipeFormTestHelpers {

    @Test func unpricedIngredientCount_EmptyBreakdown_IsZero() {
        #expect(ProductCostBreakdown().unpricedIngredientCount == 0)
    }

    @Test func unpricedIngredientCount_AllPriced_IsZero() {
        let breakdown = ProductCostBreakdown(
            oils: [.mock(cost: 2)],
            additives: [.mock(cost: 0.5)],
            fragrances: [.mock(cost: 1)],
            lye: [.mock(cost: 0.3)]
        )

        #expect(breakdown.unpricedIngredientCount == 0)
    }

    @Test func unpricedIngredientCount_UnpricedRowsInEveryGroup_CountsEach() {
        let breakdown = ProductCostBreakdown(
            oils: [.mock(cost: 2), .mock(cost: 0)],
            additives: [.mock(cost: 0)],
            fragrances: [.mock(cost: 0)],
            lye: [.mock(cost: 0)]
        )

        #expect(breakdown.unpricedIngredientCount == 4)
    }

    @Test func unpricedIngredientCount_UnpricedRowWithNoAmount_IsNotCounted() {
        let breakdown = ProductCostBreakdown(oils: [.mock(amount: 0, cost: 0)])

        #expect(breakdown.unpricedIngredientCount == 0)
    }

    @Test func wholeBatchBreakdown_OnePricedOneUnpricedOil_CountsTheUnpricedOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let priced = Ingredient(name: "Coconut Oil")
        let unpriced = Ingredient(name: "Olive Oil")
        ctx.insert(priced)
        ctx.insert(unpriced)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = priced
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(priced)
        model.addOil(unpriced)

        let breakdown = model.wholeBatchBreakdown
        #expect(breakdown.total > 0)
        #expect(breakdown.unpricedIngredientCount == 1)
    }
}

extension IngredientProductBreakdown {
    static func mock(amount: Double = 100, cost: Double) -> IngredientProductBreakdown {
        IngredientProductBreakdown(ingredient: Ingredient(name: "Ingredient"), ingredientAmount: amount, cost: cost)
    }
}
