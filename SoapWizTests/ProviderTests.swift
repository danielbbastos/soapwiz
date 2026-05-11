import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Provider")
@MainActor
struct ProviderTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeBatch(in context: ModelContext, provider: Provider? = nil) -> IngredientBatch {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(ingredient)
        let batch = IngredientBatch(
            provider: provider,
            dateOfPurchase: .now,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(batch)
        ingredient.batches.append(batch)
        return batch
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
        let batch = makeBatch(in: context, provider: provider)
        try context.save()

        provider.name = "Acme Co."
        #expect(batch.provider?.name == "Acme Co.")
    }

    @Test func deleteAllowedWhenNoBatches() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Unused")
        context.insert(provider)
        try context.save()

        #expect(provider.batches.isEmpty)
        context.delete(provider)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Provider>())
        #expect(remaining.isEmpty)
    }

    @Test func deletingProviderNullifiesBatchProvider() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Acme")
        context.insert(provider)
        let batch = makeBatch(in: context, provider: provider)
        try context.save()

        context.delete(provider)
        try context.save()

        #expect(batch.provider == nil)
    }

    @Test func batchesCountReflectsLinkedBatches() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let provider = Provider(name: "Acme")
        context.insert(provider)
        _ = makeBatch(in: context, provider: provider)
        _ = makeBatch(in: context, provider: provider)
        _ = makeBatch(in: context, provider: nil)
        try context.save()

        #expect(provider.batches.count == 2)
    }
}
