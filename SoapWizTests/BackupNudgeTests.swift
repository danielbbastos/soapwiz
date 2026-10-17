import Testing
import Foundation
@testable import SoapWiz

@Suite("Backup nudge")
@MainActor
struct BackupNudgeTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    private func withState(_ body: (BackupNudgeState) -> Void) throws {
        let suite = "BackupNudgeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(BackupNudgeState(defaults: defaults))
    }

    private func shouldShow(
        _ state: BackupNudgeState,
        now: Date,
        hasCloudCopy: Bool = false,
        isTourSandbox: Bool = false,
        batchCount: Int = 3
    ) -> Bool {
        BackupNudgePolicy.shouldShow(
            .init(hasCloudCopy: hasCloudCopy, isTourSandbox: isTourSandbox, batchCount: batchCount),
            state: state,
            now: now,
            calendar: calendar
        )
    }

    private func record(
        _ state: BackupNudgeState,
        now: Date,
        hasCloudCopy: Bool = false,
        isTourSandbox: Bool = false,
        batchCount: Int = 1
    ) {
        BackupNudgePolicy.recordFirstEligibleIfNeeded(
            .init(hasCloudCopy: hasCloudCopy, isTourSandbox: isTourSandbox, batchCount: batchCount),
            state: state,
            now: now
        )
    }

    // MARK: - State

    @Test func state_FreshDefaults_AllNil() throws {
        try withState { state in
            #expect(state.lastExportDate == nil)
            #expect(state.lastDismissDate == nil)
            #expect(state.firstEligibleDate == nil)
        }
    }

    @Test func state_RoundTripsEachKeyIndependently() throws {
        try withState { state in
            state.lastExportDate = base
            #expect(state.lastExportDate == base)
            #expect(state.lastDismissDate == nil)
            #expect(state.firstEligibleDate == nil)

            state.lastDismissDate = base.addingTimeInterval(1)
            #expect(state.lastDismissDate == base.addingTimeInterval(1))

            state.firstEligibleDate = base.addingTimeInterval(2)
            #expect(state.firstEligibleDate == base.addingTimeInterval(2))
            #expect(state.lastExportDate == base)
        }
    }

    @Test func state_SettingNil_ClearsValue() throws {
        try withState { state in
            state.lastExportDate = base
            state.lastExportDate = nil
            #expect(state.lastExportDate == nil)
        }
    }

    // MARK: - Cloud copy

    @Test func hasCloudCopy_OnlyMirrored() {
        #expect(BackupNudgePolicy.hasCloudCopy(.mirrored))
        #expect(!BackupNudgePolicy.hasCloudCopy(nil))
        #expect(!BackupNudgePolicy.hasCloudCopy(.requiresPro))
        #expect(!BackupNudgePolicy.hasCloudCopy(.offlineByChoice))
        #expect(!BackupNudgePolicy.hasCloudCopy(.notMirrored))
        #expect(!BackupNudgePolicy.hasCloudCopy(.localFallback(reason: "x")))
    }

    // MARK: - Gates

    @Test func shouldShow_Mirrored_False() throws {
        try withState { state in
            state.firstEligibleDate = base
            #expect(!shouldShow(state, now: day(100), hasCloudCopy: true))
        }
    }

    @Test func shouldShow_TourSandbox_False() throws {
        try withState { state in
            state.firstEligibleDate = base
            #expect(!shouldShow(state, now: day(100), isTourSandbox: true))
        }
    }

    @Test func shouldShow_NoBatches_False() throws {
        try withState { state in
            state.firstEligibleDate = base
            #expect(!shouldShow(state, now: day(100), batchCount: 0))
        }
    }

    // MARK: - First eligible

    @Test func shouldShow_FirstEligibleNil_False() throws {
        try withState { state in
            #expect(!shouldShow(state, now: day(100)))
        }
    }

    @Test func record_EligibleAndNil_SetsNow() throws {
        try withState { state in
            record(state, now: base)
            #expect(state.firstEligibleDate == base)
        }
    }

    @Test func record_AlreadySet_KeepsOriginal() throws {
        try withState { state in
            state.firstEligibleDate = base
            record(state, now: day(5))
            #expect(state.firstEligibleDate == base)
        }
    }

    @Test func record_NotEligible_LeavesNil() throws {
        try withState { state in
            record(state, now: base, hasCloudCopy: true)
            record(state, now: base, isTourSandbox: true)
            record(state, now: base, batchCount: 0)
            #expect(state.firstEligibleDate == nil)
        }
    }

    // MARK: - 30 day boundary

    @Test func shouldShow_FirstEligible_29Days_False_30Days_True() throws {
        try withState { state in
            state.firstEligibleDate = base
            #expect(!shouldShow(state, now: day(29)))
            #expect(shouldShow(state, now: day(30)))
        }
    }

    @Test func shouldShow_LastExport_29Days_False_30Days_True() throws {
        try withState { state in
            state.firstEligibleDate = day(-400)
            state.lastExportDate = base
            #expect(!shouldShow(state, now: day(29)))
            #expect(shouldShow(state, now: day(30)))
        }
    }

    @Test func shouldShow_LastDismiss_29Days_False_30Days_True() throws {
        try withState { state in
            state.firstEligibleDate = day(-400)
            state.lastDismissDate = base
            #expect(!shouldShow(state, now: day(29)))
            #expect(shouldShow(state, now: day(30)))
        }
    }

    @Test func shouldShow_OldExportRecentDismiss_False() throws {
        try withState { state in
            state.firstEligibleDate = day(-400)
            state.lastExportDate = day(-100)
            state.lastDismissDate = day(-10)
            #expect(!shouldShow(state, now: base))
        }
    }

    @Test func shouldShow_RecentExportOldDismiss_False() throws {
        try withState { state in
            state.firstEligibleDate = day(-400)
            state.lastDismissDate = day(-100)
            state.lastExportDate = day(-10)
            #expect(!shouldShow(state, now: base))
        }
    }

    @Test func shouldShow_AllOld_True() throws {
        try withState { state in
            state.firstEligibleDate = day(-400)
            state.lastExportDate = day(-100)
            state.lastDismissDate = day(-50)
            #expect(shouldShow(state, now: base))
        }
    }

    // MARK: - DataTransferViewModel

    @Test func lastExportedLine_Mirrored_Empty() {
        #expect(DataTransferViewModel.lastExportedLine(hasCloudCopy: true, lastExport: base).isEmpty)
    }

    @Test func lastExportedLine_NeverExported_SaysNever() {
        #expect(DataTransferViewModel.lastExportedLine(hasCloudCopy: false, lastExport: nil).hasSuffix("never"))
    }

    @Test func lastExportedLine_Exported_UsesAbbreviatedDate() {
        let line = DataTransferViewModel.lastExportedLine(hasCloudCopy: false, lastExport: base)
        #expect(line.contains(base.formatted(date: .abbreviated, time: .omitted)))
    }

    @Test func shareFinished_Completed_RecordsDate() throws {
        try withState { state in
            let sut = DataTransferViewModel(nudgeState: state)
            sut.shareFinished(completed: true, at: base)
            #expect(state.lastExportDate == base)
            #expect(sut.lastExportDate == base)
        }
    }

    @Test func init_ExistingStoredDate_IsRead() throws {
        try withState { state in
            state.lastExportDate = base
            #expect(DataTransferViewModel(nudgeState: state).lastExportDate == base)
        }
    }

    @Test func shareFinished_NotCompleted_ObservableDateUnchanged() throws {
        try withState { state in
            let sut = DataTransferViewModel(nudgeState: state)
            sut.shareFinished(completed: false, at: base)
            #expect(sut.lastExportDate == nil)
        }
    }

    @Test func shareFinished_NotCompleted_LeavesDateUnchanged() throws {
        try withState { state in
            let sut = DataTransferViewModel(nudgeState: state)
            sut.shareFinished(completed: false, at: base)
            #expect(state.lastExportDate == nil)

            state.lastExportDate = base
            sut.shareFinished(completed: false, at: day(10))
            #expect(state.lastExportDate == base)
        }
    }
}
