import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientDetailViewModel", .serialized)
@MainActor
struct IngredientDetailViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func makePurchase(quantity: Double, daysAgo: Int) throws -> IngredientPurchase {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
        return IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
    }

    @Test func sortedPurchasesDescendingByDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makePurchase(quantity: 100, daysAgo: 30)
        let newer = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.purchases.append(older)
        ingredient.purchases.append(newer)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.sortedPurchases.first === newer)
        #expect(model.sortedPurchases.last === older)
    }

    @Test func totalRemainingSumsAllPurchases() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase1 = try makePurchase(quantity: 100, daysAgo: 10)
        let purchase2 = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(purchase1); ctx.insert(purchase2)
        ingredient.purchases.append(purchase1)
        ingredient.purchases.append(purchase2)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.totalRemaining == 150)
    }

    @Test func deleteByOffsetUsesSortedOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makePurchase(quantity: 100, daysAgo: 30)
        let newer = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.purchases.append(older)
        ingredient.purchases.append(newer)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: ingredient)
        model.delete(at: IndexSet(integer: 0), context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(remaining.count == 1)
        #expect(remaining.first === older)
    }
}
