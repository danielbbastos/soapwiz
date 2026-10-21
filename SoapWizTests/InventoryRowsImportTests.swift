import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// How the inventory's rows behave around a CloudKit import: nothing refetches
/// while it runs, the merge that follows does, and a deleted row is pruned
/// meanwhile (SW-276).
@Suite("Inventory rows - imports", .serialized)
@MainActor
struct InventoryRowsImportTests: InventoryRowsTestHelpers {

    // MARK: - Import events

    @Test func handle_FinishedImport_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(
            context: container.mainContext,
            firstImport: try isolatedFirstImport(),
            fetchRows: counter.fetch
        )
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

    private func insertRemotely(_ name: String, in container: ModelContainer) throws {
        let other = ModelContext(container)
        other.insert(Ingredient(name: name, unit: "g"))
        try other.save()
    }

    @Test func handle_ImportStillRunning_DoesNotRefetch() async throws {
        let container = try makeContainer()
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        sut.settlingMerge {}

        #expect(counter.count == fetchesBefore)
    }

    @Test func settlingMerge_OnlyOtherEntitiesChanged_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
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
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            firstImport: try isolatedFirstImport(),
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
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            firstImport: try isolatedFirstImport(),
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

    // MARK: - Pruning during an import

    /// Two ingredients, the first with a purchase, saved before the rows load.
    private struct PruningSeed {
        let first: Ingredient
        let second: Ingredient
        let purchase: IngredientPurchase
    }

    private func seedForPruning(in context: ModelContext) throws -> PruningSeed {
        let first = Ingredient(name: "Olive Oil", unit: "g")
        let second = Ingredient(name: "Lye", unit: "g")
        context.insert(first)
        context.insert(second)
        let purchase = makePurchase()
        first.purchases.append(purchase)
        try context.save()
        return PruningSeed(first: first, second: second, purchase: purchase)
    }

    @Test func prune_ImportRunning_DropsDeletedIngredientWithoutFetching() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seed = try seedForPruning(in: context)
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(
            context: context,
            pruneInterval: .milliseconds(10),
            fetchRows: counter.fetch
        )
        let fetchesBefore = counter.count

        sut.handle(importStart)
        context.delete(seed.first)
        await waitUntil { sut.ingredients.count == 1 }

        #expect(sut.ingredients.count == 1)
        #expect(sut.ingredients.first === seed.second)
        #expect(counter.count == fetchesBefore)
    }

    @Test func prune_ImportRunning_DropsDeletedPurchase() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seed = try seedForPruning(in: context)
        let sut = InventoryRows(context: context, pruneInterval: .milliseconds(10))
        #expect(sut.purchases.count == 1)

        sut.handle(importStart)
        context.delete(seed.purchase)
        await waitUntil { sut.purchases.isEmpty }

        #expect(sut.purchases.isEmpty)
        #expect(sut.ingredients.count == 2)
    }

    @Test func prune_ImportRunning_DoesNotAddRowsFromTheStore() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try seedForPruning(in: context)
        let counter = InventoryFetchCounter()
        let sut = InventoryRows(
            context: context,
            pruneInterval: .milliseconds(10),
            fetchRows: counter.fetch
        )
        let fetchesBefore = counter.count

        sut.handle(importStart)
        try insertRemotely("Coconut Oil", in: container)
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.ingredients.count == 2)
        #expect(counter.count == fetchesBefore)
    }

    @Test func prune_NoImportRunning_DoesNothing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seed = try seedForPruning(in: context)
        let sut = InventoryRows(context: context, pruneInterval: .milliseconds(10))

        context.delete(seed.first)
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.ingredients.count == 2)
    }

    @Test func prune_AfterImportFinishes_Stops() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seed = try seedForPruning(in: context)
        let sut = InventoryRows(
            context: context,
            pruneInterval: .milliseconds(10),
            firstImport: try isolatedFirstImport()
        )

        sut.handle(importStart)
        sut.handle(importEnd)
        context.delete(seed.first)
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.ingredients.count == 2)
    }

}
