import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// When the merge runs. It used to follow every remote-change notification,
/// which kept the main actor busy for the whole of a first sync (SW-219).
@Suite("Duplicate merge coordinator", .serialized)
@MainActor
struct DuplicateMergeCoordinatorTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func insertDuplicateCategories(in context: ModelContext) throws {
        context.insert(IngredientCategory(name: "Oils"))
        context.insert(IngredientCategory(name: "Oils"))
        try context.save()
    }

    private func categoryCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<IngredientCategory>())
    }

    // MARK: - Import events

    @Test func shouldMerge_FinishedImport_ReturnsTrue() {
        let event = SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil)
        #expect(DuplicateMergeCoordinator.shouldMerge(after: event))
    }

    /// A failed import can stop part-way, after saving some of what it fetched.
    @Test func shouldMerge_FailedImport_ReturnsTrue() {
        let event = SyncEvent(kind: .import, endDate: .now, succeeded: false, error: nil)
        #expect(DuplicateMergeCoordinator.shouldMerge(after: event))
    }

    /// CloudKit posts each event once when it starts; merging then would scan a
    /// store the import is still writing to.
    @Test func shouldMerge_ImportStillRunning_ReturnsFalse() {
        let event = SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil)
        #expect(!DuplicateMergeCoordinator.shouldMerge(after: event))
    }

    /// An export only sends what this device already has, so it can't bring a
    /// duplicate in — and the merge's own saves cause one.
    @Test func shouldMerge_FinishedExport_ReturnsFalse() {
        let event = SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil)
        #expect(!DuplicateMergeCoordinator.shouldMerge(after: event))
    }

    @Test func shouldMerge_FinishedSetup_ReturnsFalse() {
        let event = SyncEvent(kind: .setup, endDate: .now, succeeded: true, error: nil)
        #expect(!DuplicateMergeCoordinator.shouldMerge(after: event))
    }

    // MARK: - History

    @Test func shouldMerge_NoHistoryChanges_ReturnsFalse() {
        #expect(!DuplicateMergeCoordinator.shouldMerge(historyChangeCount: 0))
    }

    @Test func shouldMerge_HistoryChanges_ReturnsTrue() {
        #expect(DuplicateMergeCoordinator.shouldMerge(historyChangeCount: 3))
    }

    @Test func shouldMerge_HistoryUnreadable_ReturnsTrue() {
        #expect(DuplicateMergeCoordinator.shouldMerge(historyChangeCount: nil))
    }

    /// Polls for up to two seconds rather than sleeping a fixed time.
    private func waitForCategoryCount(_ expected: Int, in context: ModelContext) async throws {
        for _ in 0..<200 where try categoryCount(in: context) != expected {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func importFinished_WithChanges_Merges() async throws {
        let (container, context) = try makeContext()
        let sut = DuplicateMergeCoordinator(context: context, debounce: .milliseconds(10))
        let other = ModelContext(container)
        other.insert(IngredientCategory(name: "Oils"))
        other.insert(IngredientCategory(name: "Oils"))
        try other.save()

        sut.importFinished()
        try await waitForCategoryCount(1, in: context)

        #expect(try categoryCount(in: context) == 1)
    }

    @Test func importFinished_WithoutChanges_DoesNotMerge() async throws {
        let (container, context) = try makeContext()
        _ = container
        // Saved before the coordinator exists, so its history is not news to it.
        try insertDuplicateCategories(in: context)
        let sut = DuplicateMergeCoordinator(context: context, debounce: .milliseconds(10))

        sut.importFinished()
        try await Task.sleep(for: .milliseconds(200))

        #expect(try categoryCount(in: context) == 2)
    }

    /// An empty import right after one that wrote something must not cancel the
    /// merge the first one asked for.
    @Test func importFinished_EmptyImportAfterNonEmpty_KeepsPendingMerge() async throws {
        let (container, context) = try makeContext()
        let sut = DuplicateMergeCoordinator(context: context, debounce: .milliseconds(50))
        let other = ModelContext(container)
        other.insert(IngredientCategory(name: "Oils"))
        other.insert(IngredientCategory(name: "Oils"))
        try other.save()

        sut.importFinished()
        sut.importFinished()
        try await waitForCategoryCount(1, in: context)

        #expect(try categoryCount(in: context) == 1)
    }

    // MARK: - Merging

    @Test func mergeNow_WithDuplicates_Merges() throws {
        let (container, context) = try makeContext()
        _ = container
        let sut = DuplicateMergeCoordinator(context: context)
        try insertDuplicateCategories(in: context)

        sut.mergeNow()

        #expect(try categoryCount(in: context) == 1)
    }
}
