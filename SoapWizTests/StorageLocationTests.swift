import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("StorageLocation", .serialized)
@MainActor
struct StorageLocationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePurchase(in context: ModelContext, location: StorageLocation? = nil) -> IngredientPurchase {
        let ingredient = Ingredient(name: "Olive Oil")
        context.insert(ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil,
            storageLocation: location
        )
        context.insert(purchase)
        ingredient.purchases.append(purchase)
        return purchase
    }

    @Test func createLocation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let location = StorageLocation(name: "Fridge", locationDescription: "Temperature-controlled")
        context.insert(location)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StorageLocation>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Fridge")
        #expect(fetched.first?.locationDescription == "Temperature-controlled")
    }

    @Test func renamePropagatesImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let location = StorageLocation(name: "Shelf A")
        context.insert(location)
        let purchase = makePurchase(in: context, location: location)
        try context.save()

        location.name = "Shelf B"
        #expect(purchase.storageLocation?.name == "Shelf B")
    }

    @Test func deleteAllowedWhenNoPurchases() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let location = StorageLocation(name: "Empty Shelf")
        context.insert(location)
        try context.save()

        #expect(location.purchases.isEmpty)
        context.delete(location)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<StorageLocation>())
        #expect(remaining.isEmpty)
    }

    @Test func deletingLocationNullifiesPurchaseLocation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let location = StorageLocation(name: "Fridge")
        context.insert(location)
        let purchase = makePurchase(in: context, location: location)
        try context.save()

        context.delete(location)
        try context.save()

        #expect(purchase.storageLocation == nil)
    }
}
