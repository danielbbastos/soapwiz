import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Provider", .serialized)
@MainActor
struct ProviderTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePurchase(in context: ModelContext, provider: Provider? = nil) -> IngredientPurchase {
        let ingredient = Ingredient(name: "Olive Oil")
        context.insert(ingredient)
        let purchase = IngredientPurchase(
            provider: provider,
            dateOfPurchase: .now,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        ingredient.purchases.append(purchase)
        return purchase
    }

    @Test func createProvider() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let provider = Provider(name: "Acme Soap Supplies", website: "https://acme.example", notes: "10-day lead time")
        context.insert(provider)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Provider>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Acme Soap Supplies")
        #expect(fetched.first?.website == "https://acme.example")
        #expect(fetched.first?.notes == "10-day lead time")
    }

    @Test func renamePropagatesImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Acme")
        context.insert(provider)
        let purchase = makePurchase(in: context, provider: provider)
        try context.save()

        provider.name = "Acme Co."
        #expect(purchase.provider?.name == "Acme Co.")
    }

    @Test func deleteAllowedWhenNoPurchasees() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Unused")
        context.insert(provider)
        try context.save()

        #expect(provider.purchases.isEmpty)
        context.delete(provider)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Provider>())
        #expect(remaining.isEmpty)
    }

    @Test func deletingProviderNullifiesPurchaseProvider() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Acme")
        context.insert(provider)
        let purchase = makePurchase(in: context, provider: provider)
        try context.save()

        context.delete(provider)
        try context.save()

        #expect(purchase.provider == nil)
    }

    @Test func purchaseesCountReflectsLinkedPurchasees() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Acme")
        context.insert(provider)
        _ = makePurchase(in: context, provider: provider)
        _ = makePurchase(in: context, provider: provider)
        _ = makePurchase(in: context, provider: nil)
        try context.save()

        #expect(provider.purchases.count == 2)
    }
}
