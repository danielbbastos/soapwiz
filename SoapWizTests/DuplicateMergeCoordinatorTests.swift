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

    // MARK: - Activation

    /// Launch has just merged, so the activation that follows it has nothing
    /// to find.
    @Test func appDidBecomeActive_FirstActivation_DoesNotMerge() throws {
        let (container, context) = try makeContext()
        _ = container
        let sut = DuplicateMergeCoordinator(context: context)
        try insertDuplicateCategories(in: context)

        sut.appDidBecomeActive()

        #expect(try categoryCount(in: context) == 2)
    }

    @Test func appDidBecomeActive_ReturnToForeground_Merges() throws {
        let (container, context) = try makeContext()
        _ = container
        let sut = DuplicateMergeCoordinator(context: context)
        sut.appDidBecomeActive()
        try insertDuplicateCategories(in: context)

        sut.appDidBecomeActive()

        #expect(try categoryCount(in: context) == 1)
    }

    @Test func mergeNow_BeforeAnyActivation_Merges() throws {
        let (container, context) = try makeContext()
        _ = container
        let sut = DuplicateMergeCoordinator(context: context)
        try insertDuplicateCategories(in: context)

        sut.mergeNow()

        #expect(try categoryCount(in: context) == 1)
    }
}
