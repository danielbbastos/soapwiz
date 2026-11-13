import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Purchases that share a date still sort the same way every time, so the
/// detail list, its delete offsets and the FIFO draw order all agree.
@Suite("Purchase ordering", .serialized)
@MainActor
struct PurchaseOrderingTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @discardableResult
    private func addPurchase(
        _ quantity: Double,
        on ingredient: Ingredient,
        date: Date,
        createdAt: Date? = nil,
        in ctx: ModelContext
    ) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.createdAt = createdAt
        ctx.insert(purchase)
        purchase.attach(to: ingredient)
        purchase.remainingAmount = quantity
        return purchase
    }

    private func ingredientWithTiedPurchases(in ctx: ModelContext, count: Int = 6) -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        for index in 1...count {
            addPurchase(Double(index), on: ingredient, date: day, in: ctx)
        }
        return ingredient
    }

    @Test func sortedPurchases_EqualDates_AreStableAcrossShuffledInputs() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = ingredientWithTiedPurchases(in: ctx)
        let model = IngredientDetailViewModel(ingredient: ingredient)
        let expected = model.sortedPurchases.map(\.uuid)

        for _ in 0..<10 {
            ingredient.purchases.shuffle()
            #expect(model.sortedPurchases.map(\.uuid) == expected)
        }
    }

    @Test func isNewer_EqualDates_NewerCreatedAtWins() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lye")
        ctx.insert(ingredient)
        let older = addPurchase(1, on: ingredient, date: day, createdAt: day, in: ctx)
        let newer = addPurchase(2, on: ingredient, date: day, createdAt: day.addingTimeInterval(60), in: ctx)
        let legacy = addPurchase(3, on: ingredient, date: day, createdAt: nil, in: ctx)

        let sorted = ingredient.purchases.sorted(by: IngredientPurchase.isNewer(_:than:))

        #expect(sorted.map(\.quantity) == [newer.quantity, older.quantity, legacy.quantity])
    }

    @Test func isNewer_DifferentDates_NewestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lye")
        ctx.insert(ingredient)
        addPurchase(1, on: ingredient, date: day, in: ctx)
        addPurchase(2, on: ingredient, date: day.addingTimeInterval(86_400), in: ctx)

        let sorted = ingredient.purchases.sorted(by: IngredientPurchase.isNewer(_:than:))

        #expect(sorted.map(\.quantity) == [2, 1])
    }

    @Test func delete_OffsetInDisplayedOrder_DeletesExactlyThatPurchase() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = ingredientWithTiedPurchases(in: ctx)
        try ctx.save()
        let model = IngredientDetailViewModel(ingredient: ingredient)
        let displayed = model.displayedPurchases(showingAll: true)
        let target = displayed[3]
        let survivors = displayed.filter { $0 !== target }.map(\.uuid)

        ingredient.purchases.shuffle()
        model.delete(at: IndexSet(integer: 3), from: displayed, context: ctx)

        #expect(ingredient.purchases.count == displayed.count - 1)
        #expect(!ingredient.purchases.contains { $0.uuid == target.uuid })
        #expect(model.sortedPurchases.map(\.uuid) == survivors)
    }

    @Test func delete_PreviewOnly_DeletesWithinTheDisplayedPrefix() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = ingredientWithTiedPurchases(in: ctx)
        let model = IngredientDetailViewModel(ingredient: ingredient)
        let displayed = model.displayedPurchases(showingAll: false)
        let target = displayed[1]

        model.delete(at: IndexSet(integer: 1), from: displayed, context: ctx)

        #expect(!ingredient.purchases.contains { $0.uuid == target.uuid })
        #expect(ingredient.purchases.count == 5)
    }

    @Test func delete_OffsetOutOfRange_DeletesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = ingredientWithTiedPurchases(in: ctx, count: 3)
        let model = IngredientDetailViewModel(ingredient: ingredient)

        model.delete(at: IndexSet(integer: 9), from: model.displayedPurchases(showingAll: false), context: ctx)

        #expect(ingredient.purchases.count == 3)
    }

    @Test func fifoOrder_EqualDates_OldestCreatedFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lye")
        ctx.insert(ingredient)
        let first = addPurchase(1, on: ingredient, date: day, createdAt: day, in: ctx)
        let second = addPurchase(2, on: ingredient, date: day, createdAt: day.addingTimeInterval(60), in: ctx)

        let fifo = ingredient.purchases.sorted { IngredientPurchase.isNewer($1, than: $0) }

        #expect(fifo.map(\.uuid) == [first.uuid, second.uuid])
    }
}
