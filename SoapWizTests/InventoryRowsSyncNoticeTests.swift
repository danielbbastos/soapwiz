import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The "Syncing with iCloud" notice: only while this device's first import
/// runs, and only once it has run for a moment (SW-276).
@Suite("Inventory rows - sync notice", .serialized)
@MainActor
struct InventoryRowsSyncNoticeTests: InventoryRowsTestHelpers {

    private func makeRows(
        in container: ModelContainer,
        firstImport: FirstImportRecord,
        importTimeout: Duration = .seconds(120),
        syncNoticeDelay: Duration = .milliseconds(10)
    ) -> InventoryRows {
        InventoryRows(
            context: container.mainContext,
            importTimeout: importTimeout,
            syncNoticeDelay: syncNoticeDelay,
            firstImport: firstImport
        )
    }

    @Test func isSyncing_BeforeDelay_IsFalse() throws {
        let container = try makeContainer()
        let sut = makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .seconds(60))

        sut.handle(importStart)

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_AfterDelay_IsTrueAndFalseAtFinish() async throws {
        let container = try makeContainer()
        let sut = makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .milliseconds(30))

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }
        #expect(sut.isSyncing)

        sut.handle(importEnd)
        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_FinishBeforeDelay_NeverSets() async throws {
        let container = try makeContainer()
        let sut = makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .milliseconds(50))

        sut.handle(importStart)
        sut.handle(importEnd)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_ExportEvent_IsIgnored() async throws {
        let container = try makeContainer()
        let sut = makeRows(in: container, firstImport: try isolatedFirstImport())

        sut.handle(SyncEvent(kind: .export, endDate: nil, succeeded: false, error: nil))
        try await Task.sleep(for: .milliseconds(100))

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_TimeoutFires_IsFalse() async throws {
        let container = try makeContainer()
        let sut = makeRows(
            in: container,
            firstImport: try isolatedFirstImport(),
            importTimeout: .milliseconds(100),
            syncNoticeDelay: .milliseconds(10)
        )

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }
        #expect(sut.isSyncing)
        await waitUntil { !sut.isSyncing }

        #expect(!sut.isSyncing)
    }

    // MARK: - First sync only

    @Test func isSyncing_DuringFirstImport_IsTrue() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = makeRows(in: container, firstImport: record)

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }

        #expect(sut.isSyncing)
        #expect(!record.isCompleted)
    }

    @Test func isSyncing_AfterSuccessfulFirstImport_LaterImportNeverShowsIt() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = makeRows(in: container, firstImport: record)
        sut.handle(importStart)
        sut.handle(importEnd)
        #expect(record.isCompleted)

        sut.handle(importStart)
        try await Task.sleep(for: .milliseconds(150))

        #expect(!sut.isSyncing)
    }

    @Test func isSyncing_AfterFailedFirstImport_NextImportStillShowsIt() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = makeRows(in: container, firstImport: record)
        sut.handle(importStart)
        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: false, error: nil))
        #expect(!record.isCompleted)

        sut.handle(importStart)
        await waitUntil { sut.isSyncing }

        #expect(sut.isSyncing)
    }

    @Test func firstImport_ExportFinishing_DoesNotMarkIt() throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = makeRows(in: container, firstImport: record)

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(!record.isCompleted)
    }

    @Test func firstImport_SuccessfulImport_MarksIt() throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = makeRows(in: container, firstImport: record)

        sut.handle(importStart)
        sut.handle(importEnd)

        #expect(record.isCompleted)
    }
}
