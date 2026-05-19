import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientDetailViewModel", .serialized)
@MainActor
struct IngredientDetailViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func makeBatch(quantity: Double, daysAgo: Int) throws -> IngredientBatch {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
        return IngredientBatch(
            dateOfPurchase: date, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
    }

    @Test func sortedBatchesDescendingByDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makeBatch(quantity: 100, daysAgo: 30)
        let newer = try makeBatch(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.batches.append(older)
        ingredient.batches.append(newer)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.sortedBatches.first === newer)
        #expect(model.sortedBatches.last === older)
    }

    @Test func totalRemainingSumsAllBatches() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let b1 = try makeBatch(quantity: 100, daysAgo: 10)
        let b2 = try makeBatch(quantity: 50, daysAgo: 5)
        ctx.insert(b1); ctx.insert(b2)
        ingredient.batches.append(b1)
        ingredient.batches.append(b2)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.totalRemaining == 150)
    }

    @Test func deleteByOffsetUsesSortedOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makeBatch(quantity: 100, daysAgo: 30)
        let newer = try makeBatch(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.batches.append(older)
        ingredient.batches.append(newer)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: ingredient)
        model.delete(at: IndexSet(integer: 0), context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<IngredientBatch>())
        #expect(remaining.count == 1)
        #expect(remaining.first === older)
    }
}
