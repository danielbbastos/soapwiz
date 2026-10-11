import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// When the inventory's rows refetch (SW-221). A second context stands in for
/// CloudKit: it writes to the same store without this context's `didSave`.
@Suite("Inventory rows", .serialized)
@MainActor
struct InventoryRowsTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    private func makePurchase(quantity: Double = 100) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
    }

    /// Waits for `condition`, which a background task makes true, for at most
    /// two seconds.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Initial rows

    @Test func init_LoadsRowsFromStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(ingredient)
        ingredient.purchases.append(makePurchase())
        try context.save()

        let sut = InventoryRows(context: context)

        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
        #expect(sut.purchases.count == 1)
    }

    @Test func init_EmptyStore_HasNoRows() throws {
        let container = try makeContainer()

        let sut = InventoryRows(context: container.mainContext)

        #expect(sut.ingredients.isEmpty)
        #expect(sut.purchases.isEmpty)
    }

    // MARK: - Own saves

    @Test func save_InOwnContext_RefreshesImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = InventoryRows(context: context)

        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()

        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func save_InOwnContext_AddingPurchase_RefreshesPurchases() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(ingredient)
        try context.save()
        let sut = InventoryRows(context: context)

        ingredient.purchases.append(makePurchase())
        try context.save()

        #expect(sut.purchases.count == 1)
    }

    @Test func save_InAnotherContext_DoesNotRefreshByItself() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)

        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        #expect(sut.ingredients.isEmpty)
    }

    // MARK: - History check

    @Test func refreshIfInventoryChanged_IngredientFromAnotherContext_ShowsItAndReturnsTrue() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()
        #expect(sut.ingredients.isEmpty)

        let refreshed = sut.refreshIfInventoryChanged()

        #expect(refreshed)
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func refreshIfInventoryChanged_ProviderOnlyChange_ReturnsFalse() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)
        other.insert(Provider(name: "Soap Supply"))
        try other.save()

        #expect(!sut.refreshIfInventoryChanged())
    }

    @Test func refreshIfInventoryChanged_NothingChanged_ReturnsFalse() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)

        #expect(!sut.refreshIfInventoryChanged())
    }

    @Test func refreshIfInventoryChanged_PurchaseFromAnotherContext_ReturnsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()
        let sut = InventoryRows(context: context)
        let other = ModelContext(container)
        let ingredient = try #require(try other.fetch(FetchDescriptor<Ingredient>()).first)
        ingredient.purchases.append(makePurchase())
        try other.save()

        let refreshed = sut.refreshIfInventoryChanged()

        #expect(refreshed)
        #expect(sut.purchases.count == 1)
    }

    @Test func refreshIfInventoryChanged_CategoryFromAnotherContext_ReturnsTrue() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)
        other.insert(IngredientCategory(name: "Oils"))
        try other.save()

        #expect(sut.refreshIfInventoryChanged())
    }

    @Test func refreshIfInventoryChanged_ChangeAlreadyRefreshedBySave_ReturnsFalse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = InventoryRows(context: context)
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()

        #expect(!sut.refreshIfInventoryChanged())
    }

    // MARK: - Deleted rows

    @Test func ingredients_DeletedInOwnContext_AreDropped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let doomed = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(doomed)
        context.insert(Ingredient(name: "Lye", unit: "g"))
        try context.save()
        let sut = InventoryRows(context: context)

        context.delete(doomed)
        try context.save()

        #expect(sut.ingredients.map(\.name) == ["Lye"])
        #expect(sut.ingredients.allSatisfy { !$0.isDeleted && $0.modelContext != nil })
    }

    @Test func refresh_WithDeletionPending_DropsTheDeletedRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let doomed = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(doomed)
        try context.save()
        let sut = InventoryRows(context: context)

        context.delete(doomed)
        sut.refresh()

        #expect(sut.ingredients.isEmpty)
    }

    @Test func refreshIfInventoryChanged_DeletedInAnotherContext_DropsTheRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()
        let sut = InventoryRows(context: context)
        let other = ModelContext(container)
        let remote = try #require(try other.fetch(FetchDescriptor<Ingredient>()).first)
        other.delete(remote)
        try other.save()

        let refreshed = sut.refreshIfInventoryChanged()

        #expect(refreshed)
        #expect(sut.ingredients.isEmpty)
    }

    // MARK: - Import events

    @Test func handle_FinishedImport_RefreshesWhenInventoryChanged() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil))

        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func handle_FinishedExport_DoesNothing() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(sut.ingredients.isEmpty)
    }

    @Test func handle_ImportStillRunning_PollsUntilItFinishes() async throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext, pollInterval: .milliseconds(10))
        let other = ModelContext(container)

        sut.handle(SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil))
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()
        await waitUntil { !sut.ingredients.isEmpty }
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])

        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil))
        other.insert(Ingredient(name: "Lye", unit: "g"))
        try other.save()
        try await Task.sleep(for: .milliseconds(100))
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }
}
