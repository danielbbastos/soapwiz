import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// When the batch rows refetch, and when they leave the list alone (SW-360).
@Suite("Batch rows", .serialized)
@MainActor
struct BatchRowsTests: InventoryRowsTestHelpers {

    private func lineItem() -> BatchLineItem {
        BatchLineItem(
            ingredient: nil,
            ingredientName: "Olive Oil",
            amountConsumed: 100,
            unit: "g",
            cost: 1,
            draws: []
        )
    }

    private func insertBatchWithLineItem(in context: ModelContext) throws -> BatchLineItem {
        let batch = Batch.mock()
        let item = lineItem()
        context.insert(batch)
        batch.lineItems.append(item)
        try context.save()
        return item
    }

    private func insertRemotely(_ recipeName: String, in container: ModelContainer) throws {
        let other = ModelContext(container)
        other.insert(Batch.mock(recipeName: recipeName))
        try other.save()
    }

    // MARK: - Own saves

    @Test func init_FetchesBatchesNewestFirst() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date.now
        context.insert(Batch.mock(recipeName: "Old", dateCreated: now.addingTimeInterval(-200)))
        context.insert(Batch.mock(recipeName: "New", dateCreated: now))
        context.insert(Batch.mock(recipeName: "Middle", dateCreated: now.addingTimeInterval(-100)))
        try context.save()

        let sut = BatchRows(context: context)

        #expect(sut.batches.map(\.recipeName) == ["New", "Middle", "Old"])
    }

    @Test func save_InsertsBatch_RefetchesAndShowsIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(Batch.mock(recipeName: "Lavender"))
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.map(\.recipeName) == ["Lavender"])
    }

    @Test func save_EditsLineItem_Refetches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = try insertBatchWithLineItem(in: context)
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        item.cost = 5
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.count == 1)
    }

    @Test func save_DeletesLineItem_Refetches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = try insertBatchWithLineItem(in: context)
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        context.delete(item)
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.count == 1)
    }

    @Test func save_OnlyIngredient_DoesNotRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(Ingredient(name: "Lye", unit: "g"))
        try context.save()

        #expect(counter.count == fetchesBefore)
        #expect(sut.batches.isEmpty)
    }

    @Test func save_OnlyAppSettings_DoesNotRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(AppSettings())
        try context.save()

        #expect(counter.count == fetchesBefore)
        #expect(sut.batches.isEmpty)
    }

    // MARK: - Other contexts and imports

    @Test func import_OtherContextSavesBatch_RefetchesOnlyWhenImportFinishes() throws {
        let container = try makeContainer()
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: container.mainContext, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        try insertRemotely("Lavender", in: container)
        #expect(counter.count == fetchesBefore)
        #expect(sut.batches.isEmpty)

        sut.handle(importEnd)

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.map(\.recipeName) == ["Lavender"])
    }

    @Test func import_OnlyUnrelatedChanges_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: container.mainContext, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        sut.handle(importEnd)

        #expect(counter.count == fetchesBefore)
    }

    @Test func handle_Export_DoesNothing() throws {
        let container = try makeContainer()
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: container.mainContext, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count
        try insertRemotely("Lavender", in: container)

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(counter.count == fetchesBefore)
    }

    // MARK: - Deferral and merge

    @Test func deferringRefreshes_SeveralBatchSaves_RefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        sut.deferringRefreshes {
            for name in ["A", "B", "C"] {
                context.insert(Batch.mock(recipeName: name))
                try? context.save()
            }
            #expect(counter.count == fetchesBefore)
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.count == 3)
    }

    @Test func settlingMerge_MergeSavesBatches_RefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        sut.settlingMerge {
            context.insert(Batch.mock(recipeName: "A"))
            try? context.save()
            context.insert(Batch.mock(recipeName: "B"))
            try? context.save()
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.count == 2)
    }

    // MARK: - Pruning

    @Test func prune_ImportRunning_DropsDeletedBatchWithoutFetching() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Batch.mock(recipeName: "First", dateCreated: .now)
        let second = Batch.mock(recipeName: "Second", dateCreated: .now.addingTimeInterval(-10))
        context.insert(first)
        context.insert(second)
        try context.save()
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, pruneInterval: .milliseconds(10), fetchBatches: counter.fetch)
        let fetchesBefore = counter.count
        #expect(sut.batches.count == 2)

        sut.handle(importStart)
        context.delete(first)
        await waitUntil { sut.batches.count == 1 }

        #expect(sut.batches.count == 1)
        #expect(sut.batches.first === second)
        #expect(counter.count == fetchesBefore)
    }

    // MARK: - Failures and timeout

    @Test func fetch_Fails_KeepsOldRowsAndNextCheckRetries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: context, fetchBatches: counter.fetch)
        context.insert(Batch.mock(recipeName: "Lavender"))
        try context.save()
        #expect(sut.batches.count == 1)

        counter.shouldFail = true
        context.insert(Batch.mock(recipeName: "Rose"))
        try context.save()
        #expect(sut.batches.map(\.recipeName) == ["Lavender"])

        counter.shouldFail = false
        let fetchesBefore = counter.count
        let didRefetch = sut.refreshIfBatchesChanged()

        #expect(didRefetch)
        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.count == 2)
    }

    @Test func refreshIfBatchesChanged_NothingChanged_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = BatchFetchCounter()
        let sut = BatchRows(context: container.mainContext, fetchBatches: counter.fetch)
        let fetchesBefore = counter.count

        let didRefetch = sut.refreshIfBatchesChanged()

        #expect(!didRefetch)
        #expect(counter.count == fetchesBefore)
    }

    @Test func handle_ImportNeverFinishes_RefetchesAfterTimeoutWhenHistoryChanged() async throws {
        let container = try makeContainer()
        let counter = BatchFetchCounter()
        let sut = BatchRows(
            context: container.mainContext,
            importTimeout: .milliseconds(50),
            fetchBatches: counter.fetch
        )
        let fetchesBefore = counter.count
        try insertRemotely("Lavender", in: container)

        sut.handle(importStart)
        #expect(counter.count == fetchesBefore)
        await waitUntil { counter.count > fetchesBefore }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.batches.map(\.recipeName) == ["Lavender"])
    }
}
