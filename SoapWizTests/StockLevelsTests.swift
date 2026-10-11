import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Stock levels")
@MainActor
struct StockLevelsTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func makeIngredient(_ name: String, threshold: Double? = nil) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(remaining: Double, to ingredient: Ingredient?) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        context.insert(purchase)
        if let ingredient {
            ingredient.purchases.append(purchase)
        }
        return purchase
    }

    @Test func totalRemaining_MultiplePurchases_SumsPerIngredient() {
        let olive = makeIngredient("Olive")
        let lye = makeIngredient("Lye")
        let purchases = [
            addPurchase(remaining: 300, to: olive),
            addPurchase(remaining: 200, to: olive),
            addPurchase(remaining: 50, to: lye)
        ]

        let sut = StockLevels(purchases)

        #expect(sut.totalRemaining(olive) == 500)
        #expect(sut.totalRemaining(lye) == 50)
        #expect(sut.hasPurchases(olive))
        #expect(sut.hasPurchases(lye))
    }

    @Test func init_PurchaseWithoutIngredient_IsIgnored() {
        let olive = makeIngredient("Olive")
        let purchases = [
            addPurchase(remaining: 300, to: olive),
            addPurchase(remaining: 999, to: nil)
        ]

        let sut = StockLevels(purchases)

        #expect(sut.totalRemaining(olive) == 300)
    }

    @Test func totalRemaining_NoPurchases_IsZeroAndHasNone() {
        let olive = makeIngredient("Olive", threshold: 100)

        let sut = StockLevels([])

        #expect(!sut.hasPurchases(olive))
        #expect(sut.totalRemaining(olive) == 0)
    }

    @Test func isLowStock_AtThreshold_ReturnsTrue() {
        let olive = makeIngredient("Olive", threshold: 100)
        let purchases = [addPurchase(remaining: 100, to: olive)]

        let sut = StockLevels(purchases)

        #expect(sut.isLowStock(olive))
    }

    @Test func isLowStock_AboveThreshold_ReturnsFalse() {
        let olive = makeIngredient("Olive", threshold: 100)
        let purchases = [addPurchase(remaining: 101, to: olive)]

        let sut = StockLevels(purchases)

        #expect(!sut.isLowStock(olive))
    }

    @Test func isLowStock_NoThreshold_ReturnsFalse() {
        let olive = makeIngredient("Olive")
        let purchases = [addPurchase(remaining: 0, to: olive)]

        let sut = StockLevels(purchases)

        #expect(!sut.isLowStock(olive))
    }

    @Test func isLowStock_AgreesWithIngredient() {
        let olive = makeIngredient("Olive", threshold: 100)
        let purchases = [addPurchase(remaining: 60, to: olive), addPurchase(remaining: 40, to: olive)]

        let sut = StockLevels(purchases)

        #expect(sut.isLowStock(olive) == olive.isLowStock)
        #expect(sut.totalRemaining(olive) == olive.totalRemaining)
    }
}
