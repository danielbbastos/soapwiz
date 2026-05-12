import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient.nearestUpcomingExpiry")
@MainActor
struct IngredientExpiryTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func makeBatch(expiryDate: Date?) -> IngredientBatch {
        IngredientBatch(
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: expiryDate, openingDate: nil
        )
    }

    @Test func returnsNilWhenNoBatches() throws {
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
        let batch = makeBatch(expiryDate: nil)
        ctx.insert(batch)
        ingredient.batches.append(batch)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsNilWhenExpiryAlreadyPassed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let expired = makeBatch(expiryDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        ctx.insert(expired)
        ingredient.batches.append(expired)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsNilWhenExpiryBeyond30Days() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        let farFuture = makeBatch(expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: cutoff)!)
        ctx.insert(farFuture)
        ingredient.batches.append(farFuture)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func returnsDateWhenExpiryWithin30Days() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let soon = Calendar.current.date(byAdding: .day, value: 15, to: .now)!
        let batch = makeBatch(expiryDate: soon)
        ctx.insert(batch)
        ingredient.batches.append(batch)
        let result = ingredient.nearestUpcomingExpiry
        #expect(result != nil)
        #expect(abs(result!.timeIntervalSince(soon)) < 1)
    }

    @Test func returnsNearestWhenMultipleBatchesExpiring() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let sooner = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let later = Calendar.current.date(byAdding: .day, value: 20, to: .now)!
        let b1 = makeBatch(expiryDate: sooner)
        let b2 = makeBatch(expiryDate: later)
        ctx.insert(b1); ctx.insert(b2)
        ingredient.batches.append(b1)
        ingredient.batches.append(b2)
        let result = ingredient.nearestUpcomingExpiry
        #expect(result != nil)
        #expect(abs(result!.timeIntervalSince(sooner)) < 1)
    }

    @Test func ignoresExpiredWhenMixedWithUpcoming() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Test")
        ctx.insert(ingredient)
        let past = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let future = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let b1 = makeBatch(expiryDate: past)
        let b2 = makeBatch(expiryDate: future)
        ctx.insert(b1); ctx.insert(b2)
        ingredient.batches.append(b1)
        ingredient.batches.append(b2)
        let result = ingredient.nearestUpcomingExpiry
        #expect(result != nil)
        #expect(abs(result!.timeIntervalSince(future)) < 1)
    }
}
