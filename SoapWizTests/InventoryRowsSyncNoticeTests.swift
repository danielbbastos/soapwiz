import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The Inventory's sync notice: for this device's first import and for one
/// after a long gap, and only once it has run for a moment (SW-276).
@Suite("Inventory rows - sync notice", .serialized)
@MainActor
struct InventoryRowsSyncNoticeTests: InventoryRowsTestHelpers {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: -days, to: now))
    }

    private func makeRows(
        in container: ModelContainer,
        firstImport: FirstImportRecord,
        syncStatus: SyncStatusStore? = nil,
        importTimeout: Duration = .seconds(120),
        syncNoticeDelay: Duration = .milliseconds(10)
    ) throws -> InventoryRows {
        let fixedNow = now
        return InventoryRows(
            context: container.mainContext,
            importTimeout: importTimeout,
            syncNoticeDelay: syncNoticeDelay,
            firstImport: firstImport,
            syncStatus: try syncStatus ?? isolatedSyncStatus(),
            now: { fixedNow }
        )
    }

    /// A device that has completed its first import and last synced `days` ago.
    private func returningDevice(
        in container: ModelContainer,
        lastSyncDaysAgo days: Int?
    ) throws -> InventoryRows {
        let record = try isolatedFirstImport()
        record.markCompleted()
        let status = try isolatedSyncStatus()
        if let days { status.lastSuccessfulSync = try daysAgo(days) }
        return try makeRows(in: container, firstImport: record, syncStatus: status)
    }

    // MARK: - Timing

    @Test func syncNotice_BeforeDelay_IsNil() throws {
        let container = try makeContainer()
        let sut = try makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .seconds(60))

        sut.handle(importStart)

        #expect(sut.syncNotice == nil)
    }

    @Test func syncNotice_AfterDelay_IsSetAndClearedAtFinish() async throws {
        let container = try makeContainer()
        let sut = try makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .milliseconds(30))

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }
        #expect(sut.syncNotice == .firstSync)

        sut.handle(importEnd)
        #expect(sut.syncNotice == nil)
    }

    @Test func syncNotice_FinishBeforeDelay_NeverSets() async throws {
        let container = try makeContainer()
        let sut = try makeRows(in: container, firstImport: try isolatedFirstImport(), syncNoticeDelay: .milliseconds(50))

        sut.handle(importStart)
        sut.handle(importEnd)
        try await Task.sleep(for: .milliseconds(200))

        #expect(sut.syncNotice == nil)
    }

    @Test func syncNotice_ExportEvent_IsIgnored() async throws {
        let container = try makeContainer()
        let sut = try makeRows(in: container, firstImport: try isolatedFirstImport())

        sut.handle(SyncEvent(kind: .export, endDate: nil, succeeded: false, error: nil))
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.syncNotice == nil)
    }

    @Test func syncNotice_TimeoutFires_IsCleared() async throws {
        let container = try makeContainer()
        let sut = try makeRows(
            in: container,
            firstImport: try isolatedFirstImport(),
            importTimeout: .milliseconds(100),
            syncNoticeDelay: .milliseconds(10)
        )

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }
        #expect(sut.syncNotice != nil)
        await waitUntil { sut.syncNotice == nil }

        #expect(sut.syncNotice == nil)
    }

    // MARK: - First sync

    @Test func syncNotice_DuringFirstImport_IsFirstSync() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = try makeRows(in: container, firstImport: record)

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }

        #expect(sut.syncNotice == .firstSync)
        #expect(!record.isCompleted)
    }

    @Test func syncNotice_AfterFailedFirstImport_NextImportIsStillFirstSync() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = try makeRows(in: container, firstImport: record)
        sut.handle(importStart)
        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: false, error: nil))
        #expect(!record.isCompleted)

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }

        #expect(sut.syncNotice == .firstSync)
    }

    @Test func firstImport_ExportFinishing_DoesNotMarkIt() throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = try makeRows(in: container, firstImport: record)

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(!record.isCompleted)
    }

    @Test func firstImport_SuccessfulImport_MarksIt() throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        let sut = try makeRows(in: container, firstImport: record)

        sut.handle(importStart)
        sut.handle(importEnd)

        #expect(record.isCompleted)
    }

    // MARK: - Catching up after a gap

    @Test func syncNotice_LastSyncEightDaysAgo_IsCatchingUp() async throws {
        let container = try makeContainer()
        let sut = try returningDevice(in: container, lastSyncDaysAgo: 8)

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }

        #expect(sut.syncNotice == .catchingUp)
    }

    @Test func syncNotice_LastSyncSixDaysAgo_StaysNil() async throws {
        let container = try makeContainer()
        let sut = try returningDevice(in: container, lastSyncDaysAgo: 6)

        sut.handle(importStart)
        try await Task.sleep(for: .milliseconds(150))

        #expect(sut.syncNotice == nil)
    }

    @Test func syncNotice_CompletedButNoRecordedSync_IsCatchingUp() async throws {
        let container = try makeContainer()
        let sut = try returningDevice(in: container, lastSyncDaysAgo: nil)

        sut.handle(importStart)
        await waitUntil { sut.syncNotice != nil }

        #expect(sut.syncNotice == .catchingUp)
    }

    @Test func syncNotice_CatchingUpFinishingBeforeDelay_NeverShows() async throws {
        let container = try makeContainer()
        let record = try isolatedFirstImport()
        record.markCompleted()
        let status = try isolatedSyncStatus()
        status.lastSuccessfulSync = try daysAgo(30)
        let sut = try makeRows(in: container, firstImport: record, syncStatus: status, syncNoticeDelay: .milliseconds(50))

        sut.handle(importStart)
        sut.handle(importEnd)
        try await Task.sleep(for: .milliseconds(200))

        #expect(sut.syncNotice == nil)
    }
}
