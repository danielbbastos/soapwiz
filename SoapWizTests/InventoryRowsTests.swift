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

    @Test func save_InOwnContext_AddingCategory_Refreshes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = InventoryRows(context: context)
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        context.insert(IngredientCategory(name: "Oils"))
        try context.save()

        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func save_InOwnContext_OnlyNonInventoryEntity_DoesNotRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = InventoryRows(context: context)
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        context.insert(Provider(name: "Soap Supply"))
        try context.save()

        #expect(sut.ingredients.isEmpty)
        #expect(sut.refreshIfInventoryChanged())
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
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

    @Test func handle_FinishedImport_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        sut.handle(SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil))
        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil))

        #expect(counter.count == fetchesBefore)
        #expect(sut.ingredients.isEmpty)
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

    /// Counts the fetches the inventory makes.
    @MainActor
    private final class CountingFetch {
        private(set) var count = 0

        func fetch(_ context: ModelContext) throws -> InventoryRows.FetchedRows {
            count += 1
            return try InventoryRows.fetchAll(in: context)
        }
    }

    private let importStart = SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil)
    private let importEnd = SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil)

    private func insertRemotely(_ name: String, in container: ModelContainer) throws {
        let other = ModelContext(container)
        other.insert(Ingredient(name: name, unit: "g"))
        try other.save()
    }

    @Test func handle_ImportStillRunning_DoesNotRefetch() async throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        sut.handle(importStart)
        try insertRemotely("Olive Oil", in: container)
        try await Task.sleep(for: .milliseconds(100))

        #expect(counter.count == fetchesBefore)
        #expect(sut.ingredients.isEmpty)
    }

    // MARK: - After a merge

    @Test func settlingMerge_ImportWroteInventory_RefetchesOnce() throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count
        try insertRemotely("Olive Oil", in: container)

        sut.settlingMerge {}

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func settlingMerge_MergeSavedAndImportWrote_RefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count
        try insertRemotely("Olive Oil", in: container)

        sut.settlingMerge {
            context.insert(Ingredient(name: "Lye", unit: "g"))
            try? context.save()
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.count == 2)
    }

    @Test func settlingMerge_MergeSavedOnly_RefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        sut.settlingMerge {
            context.insert(Ingredient(name: "Lye", unit: "g"))
            try? context.save()
        }

        #expect(counter.count == fetchesBefore + 1)
    }

    @Test func settlingMerge_NothingChanged_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        sut.settlingMerge {}

        #expect(counter.count == fetchesBefore)
    }

    @Test func settlingMerge_OnlyOtherEntitiesChanged_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count
        let other = ModelContext(container)
        other.insert(AppSettings())
        try other.save()

        sut.settlingMerge {}

        #expect(counter.count == fetchesBefore)
    }

    // MARK: - Import timeout

    @Test func handle_ImportNeverFinishes_RefreshesOnceAfterTimeout() async throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            fetchRows: counter.fetch
        )
        let fetchesBefore = counter.count
        try insertRemotely("Olive Oil", in: container)

        sut.handle(importStart)
        #expect(counter.count == fetchesBefore)
        await waitUntil { counter.count > fetchesBefore }
        try await Task.sleep(for: .milliseconds(150))

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func handle_ImportFinishesBeforeTimeout_NeverRefreshes() async throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            fetchRows: counter.fetch
        )
        let fetchesBefore = counter.count
        try insertRemotely("Olive Oil", in: container)

        sut.handle(importStart)
        sut.handle(importEnd)
        try await Task.sleep(for: .milliseconds(200))

        #expect(counter.count == fetchesBefore)
    }

    @Test func handle_SecondImportStart_RestartsTheTimeout() async throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            fetchRows: counter.fetch
        )
        let fetchesBefore = counter.count
        try insertRemotely("Olive Oil", in: container)

        sut.handle(importStart)
        sut.handle(importEnd)
        sut.handle(importStart)
        await waitUntil { counter.count > fetchesBefore }

        #expect(counter.count == fetchesBefore + 1)
    }

    // MARK: - Sync notice

    @Test func isSyncing_BeforeDelay_IsFalse() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext, syncNoticeDelay: .seconds(60))

        sut.handle(importStart)

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_AfterDelay_IsTrueAndFalseAtFinish() async throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext, syncNoticeDelay: .milliseconds(30))

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }
        #expect(sut.isSyncing)

        sut.handle(importEnd)
        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_FinishBeforeDelay_NeverSets() async throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext, syncNoticeDelay: .milliseconds(50))

        sut.handle(importStart)
        sut.handle(importEnd)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_ExportEvent_IsIgnored() async throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext, syncNoticeDelay: .milliseconds(10))

        sut.handle(SyncEvent(kind: .export, endDate: nil, succeeded: false, error: nil))
        try await Task.sleep(for: .milliseconds(100))

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_TimeoutFires_IsFalse() async throws {
        let container = try makeContainer()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(100),
            syncNoticeDelay: .milliseconds(10)
        )

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }
        #expect(sut.isSyncing)
        await waitUntil { !sut.isSyncing }

        #expect(!sut.isSyncing)
    }

    // MARK: - Failed fetches

    private struct FetchFailure: Error {}

    /// A fetch that throws while `failing` is true and reads the store otherwise.
    @MainActor
    private final class FlakyFetch {
        var failing = true

        func fetch(_ context: ModelContext) throws -> InventoryRows.FetchedRows {
            if failing { throw FetchFailure() }
            return try InventoryRows.fetchAll(in: context)
        }
    }

    @Test func refreshIfInventoryChanged_AfterFailedReload_RetriesAndReturnsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()
        let flaky = FlakyFetch()
        flaky.failing = false
        let sut = InventoryRows(context: context, fetchRows: flaky.fetch)
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
        flaky.failing = true
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Lye", unit: "g"))
        try other.save()

        #expect(sut.refreshIfInventoryChanged())
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])

        flaky.failing = false
        let retried = sut.refreshIfInventoryChanged()

        #expect(retried)
        #expect(Set(sut.ingredients.map(\.name)) == ["Olive Oil", "Lye"])
    }

    @Test func refreshIfInventoryChanged_AfterSuccessfulRetry_ReturnsFalse() throws {
        let container = try makeContainer()
        let flaky = FlakyFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: flaky.fetch)
        #expect(sut.refreshIfInventoryChanged())
        flaky.failing = false
        #expect(sut.refreshIfInventoryChanged())

        #expect(!sut.refreshIfInventoryChanged())
    }

    // MARK: - Save classification

    @Test func touchesInventory_WatchedEntityNames_ReturnsTrue() {
        #expect(InventoryRows.touchesInventory(entityNames: [Schema.entityName(for: Ingredient.self)]))
        #expect(InventoryRows.touchesInventory(entityNames: [Schema.entityName(for: IngredientPurchase.self)]))
        #expect(InventoryRows.touchesInventory(entityNames: [Schema.entityName(for: IngredientCategory.self)]))
    }

    @Test func touchesInventory_OtherOrNoEntityNames_ReturnsFalse() {
        #expect(!InventoryRows.touchesInventory(entityNames: [Schema.entityName(for: Provider.self)]))
        #expect(!InventoryRows.touchesInventory(entityNames: [String]()))
    }

    @Test func touchesInventory_MixedEntityNames_ReturnsTrue() {
        let names = [Schema.entityName(for: Provider.self), Schema.entityName(for: Ingredient.self)]

        #expect(InventoryRows.touchesInventory(entityNames: names))
    }

    @Test func savedEntityNames_MissingOrUnreadableUserInfo_ReturnsNil() {
        #expect(InventoryRows.savedEntityNames(from: nil) == nil)
        #expect(InventoryRows.savedEntityNames(from: [:]) == nil)
        #expect(InventoryRows.savedEntityNames(from: [
            ModelContext.NotificationKey.insertedIdentifiers.rawValue: "not identifiers"
        ]) == nil)
    }
}
