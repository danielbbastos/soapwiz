import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient.nearestUpcomingExpiry", .serialized)
@MainActor
struct IngredientExpiryTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func makePurchase(expiryDate: Date?) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: expiryDate, openingDate: nil
        )
    }

    @Test func returnsNilWhenNoPurchases() throws {
        let container = try makeContainer()
        let ingredient = Ingredient(name: "Test")
        container.mainContext.insert(ingredient)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsNilWhenNoExpiryDates() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let purchase = makePurchase(expiryDate: nil)
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsNilWhenExpiryAlreadyPassed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let expired = makePurchase(expiryDate: try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now)))
        ctx.insert(expired)
        ingredient.purchases.append(expired)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsNilWhenExpiryBeyond30Days() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let cutoff = try #require(Calendar.current.date(byAdding: .month, value: 1, to: .now))
        let farFuture = makePurchase(expiryDate: try #require(Calendar.current.date(byAdding: .day, value: 1, to: cutoff)))
        ctx.insert(farFuture)
        ingredient.purchases.append(farFuture)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsDateWhenExpiryWithin30Days() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let soon = try #require(Calendar.current.date(byAdding: .day, value: 15, to: .now))
        let purchase = makePurchase(expiryDate: soon)
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        let result = try #require(ingredient.nearestUpcomingExpiry)
        #expect(abs(result.timeIntervalSince(soon)) < 1)
    }

    @Test func returnsNearestWhenMultiplePurchasesExpiring() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let sooner = try #require(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let later = try #require(Calendar.current.date(byAdding: .day, value: 20, to: .now))
        let b1 = makePurchase(expiryDate: sooner)
        let b2 = makePurchase(expiryDate: later)
        ctx.insert(b1); ctx.insert(b2)
        ingredient.purchases.append(b1)
        ingredient.purchases.append(b2)
        let result = try #require(ingredient.nearestUpcomingExpiry)
        #expect(abs(result.timeIntervalSince(sooner)) < 1)
    }

    @Test func ignoresExpiredWhenMixedWithUpcoming() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let past = try #require(Calendar.current.date(byAdding: .day, value: -5, to: .now))
        let future = try #require(Calendar.current.date(byAdding: .day, value: 10, to: .now))
        let b1 = makePurchase(expiryDate: past)
        let b2 = makePurchase(expiryDate: future)
        ctx.insert(b1); ctx.insert(b2)
        ingredient.purchases.append(b1)
        ingredient.purchases.append(b2)
        let result = try #require(ingredient.nearestUpcomingExpiry)
        #expect(abs(result.timeIntervalSince(future)) < 1)
    }
}
