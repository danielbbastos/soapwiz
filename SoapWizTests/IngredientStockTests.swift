import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient stock")
@MainActor
struct IngredientStockTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func makeIngredient(_ name: String = "Olive") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(
        remaining: Double,
        expiry: Date? = nil,
        to ingredient: Ingredient?
    ) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: expiry,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        context.insert(purchase)
        if let ingredient {
            ingredient.purchases.append(purchase)
        }
        return purchase
    }

    private func levels() throws -> StockLevels {
        StockLevels(try context.fetch(FetchDescriptor<IngredientPurchase>()))
    }

    @Test func stock_MultiplePurchases_SumsRemainingAndHasPurchases() {
        let olive = makeIngredient()
        let lye = makeIngredient("Lye")
        let purchases = [
            addPurchase(remaining: 300, to: olive),
            addPurchase(remaining: 200, to: olive),
            addPurchase(remaining: 50, to: lye)
        ]

        let sut = StockLevels(purchases)

        #expect(sut.stock(for: olive).remaining == 500)
        #expect(sut.stock(for: olive).hasPurchases)
        #expect(sut.stock(for: lye).remaining == 50)
    }

    @Test func stock_PurchaseWithoutIngredient_IsSkipped() {
        let olive = makeIngredient()
        let purchases = [
            addPurchase(remaining: 300, to: olive),
            addPurchase(remaining: 999, to: nil)
        ]

        let sut = StockLevels(purchases)

        #expect(sut.stock(for: olive).remaining == 300)
    }

    @Test func stock_NoPurchases_IsNone() {
        let olive = makeIngredient()

        let sut = StockLevels([])

        #expect(sut.stock(for: olive) == .none)
        #expect(!sut.stock(for: olive).hasPurchases)
        #expect(sut.stock(for: olive).expiries.isEmpty)
    }

    @Test func stock_Expiries_AreCollectedSortedAndSkipNil() throws {
        let olive = makeIngredient()
        let early = try #require(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let late = try #require(Calendar.current.date(byAdding: .day, value: 20, to: .now))
        let purchases = [
            addPurchase(remaining: 1, expiry: late, to: olive),
            addPurchase(remaining: 1, expiry: nil, to: olive),
            addPurchase(remaining: 1, expiry: early, to: olive)
        ]

        let sut = StockLevels(purchases)

        #expect(sut.stock(for: olive).expiries == [early, late])
    }

    @Test func stock_SamePurchasesInAnyOrder_AreEqual() throws {
        let olive = makeIngredient()
        let early = try #require(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let late = try #require(Calendar.current.date(byAdding: .day, value: 20, to: .now))
        let first = addPurchase(remaining: 1, expiry: early, to: olive)
        let second = addPurchase(remaining: 2, expiry: late, to: olive)

        let forward = StockLevels([first, second]).stock(for: olive)
        let backward = StockLevels([second, first]).stock(for: olive)

        #expect(forward == backward)
    }

    @Test func stock_AfterDeletingAPurchase_DiffersAndDropsItsRemaining() throws {
        let olive = makeIngredient()
        addPurchase(remaining: 300, to: olive)
        let doomed = addPurchase(remaining: 200, to: olive)
        try context.save()
        let before = try levels().stock(for: olive)

        context.delete(doomed)
        try context.save()
        let after = try levels().stock(for: olive)

        #expect(after != before)
        #expect(after.remaining == before.remaining - 200)
    }

    @Test func stock_AfterDeletingTheLastPurchase_BecomesNone() throws {
        let olive = makeIngredient()
        let only = addPurchase(remaining: 300, to: olive)
        try context.save()
        let before = try levels().stock(for: olive)

        context.delete(only)
        try context.save()
        let after = try levels().stock(for: olive)

        #expect(after != before)
        #expect(after == .none)
    }

    @Test func stock_AfterAddingAPurchase_DiffersAndGainsItsRemaining() throws {
        let olive = makeIngredient()
        addPurchase(remaining: 300, to: olive)
        try context.save()
        let before = try levels().stock(for: olive)

        addPurchase(remaining: 150, to: olive)
        try context.save()
        let after = try levels().stock(for: olive)

        #expect(after != before)
        #expect(after.remaining == before.remaining + 150)
    }
}
