import CloudKit
import Foundation
import Testing
@testable import SoapWiz

@Suite(.serialized)
@MainActor
final class SyncHealthMonitorTests {

    /// A throwaway suite per test, so nothing leaks into `.standard` or between
    /// tests. `nonisolated` so `deinit` can tear it down again.
    nonisolated private let defaults: UserDefaults
    nonisolated private let suiteName: String

    init() throws {
        suiteName = "SyncHealthMonitorTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func health_MirroredLaunch_StartsUndecidedRatherThanHealthy() {
        let monitor = makeMonitor()
        #expect(monitor.health == .starting)
    }

    @Test func health_FallbackLaunch_ReportsTheReason() {
        let monitor = makeMonitor(activeStore: .localFallback(reason: "no container"))
        #expect(monitor.health == .localFallback(reason: "no container"))
    }

    @Test func health_BuildWithoutCloudKit_ReportsNotMirrored() {
        let monitor = makeMonitor(activeStore: .notMirrored)
        #expect(monitor.health == .notMirrored)
    }

    @Test func health_NoStoreRecorded_ReportsNotMirrored() {
        let monitor = makeMonitor(activeStore: nil)
        #expect(monitor.health == .notMirrored)
    }

    @Test func lastSuccessfulSync_AfterAnImport_IsRecorded() throws {
        let monitor = makeMonitor()
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)

        monitor.apply(SyncEvent(kind: .import, endDate: syncedAt, succeeded: true, error: nil))

        #expect(monitor.lastSuccessfulSync == syncedAt)
    }

    /// Without persistence the row reads "Synced" with no date on every cold
    /// launch, which is indistinguishable from never having synced.
    @Test func lastSuccessfulSync_AcrossRelaunch_Survives() {
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = makeMonitor()
        first.apply(SyncEvent(kind: .export, endDate: syncedAt, succeeded: true, error: nil))

        let relaunched = makeMonitor()

        #expect(relaunched.lastSuccessfulSync == syncedAt)
    }

    @Test func lastSuccessfulSync_SetupOnly_StaysUnset() {
        let monitor = makeMonitor()

        monitor.apply(.succeeded(.setup))

        #expect(monitor.lastSuccessfulSync == nil)
    }

    @Test func lastSuccessfulSync_FailedImport_IsNotRecorded() {
        let monitor = makeMonitor()

        monitor.apply(.failed(.import, error: ckError(.badContainer)))

        #expect(monitor.lastSuccessfulSync == nil)
    }

    /// A fallback on one launch has to outlive that launch — the next one may
    /// mirror perfectly and leave no other trace that a stretch of writes went
    /// to a store that was not syncing.
    @Test func unresolvedFallback_RecordedThenMirroredLaunch_IsReported() {
        let fellBackAt = Date(timeIntervalSince1970: 1_700_000_000)
        store().recordLocalFallback(reason: "no container", at: fellBackAt)

        let monitor = makeMonitor()

        #expect(monitor.unresolvedFallback == fellBackAt)
    }

    @Test func unresolvedFallback_AfterALaterSync_GoesQuiet() {
        let fellBackAt = Date(timeIntervalSince1970: 1_700_000_000)
        store().recordLocalFallback(reason: "no container", at: fellBackAt)
        let monitor = makeMonitor()

        monitor.apply(SyncEvent(
            kind: .export,
            endDate: fellBackAt.addingTimeInterval(60),
            succeeded: true,
            error: nil
        ))

        #expect(monitor.unresolvedFallback == nil)
    }

    /// A sync that predates the fallback proves nothing about the writes made
    /// after it.
    @Test func unresolvedFallback_SyncOlderThanTheFallback_StaysReported() {
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fellBackAt = syncedAt.addingTimeInterval(3600)
        let statusStore = store()
        statusStore.lastSuccessfulSync = syncedAt
        statusStore.recordLocalFallback(reason: "no container", at: fellBackAt)

        let monitor = makeMonitor(store: statusStore)

        #expect(monitor.unresolvedFallback == fellBackAt)
    }

    /// The current launch's own fallback is already the headline state; the
    /// footer would otherwise say it twice.
    @Test func unresolvedFallback_DuringAFallbackLaunch_IsNotRepeated() {
        store().recordLocalFallback(reason: "no container")

        let monitor = makeMonitor(activeStore: .localFallback(reason: "no container"))

        #expect(monitor.unresolvedFallback == nil)
    }

    @Test func unresolvedFallback_NoFallbackEverRecorded_IsNil() {
        let monitor = makeMonitor()
        #expect(monitor.unresolvedFallback == nil)
    }

    /// The state the simulator actually produces with no iCloud account: Core
    /// Data hands the event a bare `NSCocoaErrorDomain 134400` with an empty
    /// userInfo, so the error alone classifies as an unexplained fault. Asking
    /// CloudKit for the account status is what turns it back into the benign,
    /// self-correcting state it really is.
    @Test func refine_UnexplainedFailureWithNoAccount_BecomesSignedOut() async {
        let monitor = makeMonitor(account: .noAccount)
        monitor.apply(.failed(.setup, error: cocoaCloudKitError()))
        #expect(monitor.health == .failed(.other(cocoaCloudKitError().localizedDescription)))

        await monitor.refineUnexplainedFailure()

        #expect(monitor.health == .signedOut)
    }

    /// There is an account, so whatever went wrong is not the account. Inventing
    /// "not signed in" here would send the user to fix something that is not broken.
    @Test func refine_UnexplainedFailureWithAnAccount_StaysAFault() async {
        let monitor = makeMonitor(account: .available)
        let error = cocoaCloudKitError()
        monitor.apply(.failed(.setup, error: error))

        await monitor.refineUnexplainedFailure()

        #expect(monitor.health == .failed(.other(error.localizedDescription)))
    }

    @Test func refine_UnexplainedFailureWhenRestricted_ReportsPermissionDenied() async {
        let monitor = makeMonitor(account: .restricted)
        monitor.apply(.failed(.setup, error: cocoaCloudKitError()))

        await monitor.refineUnexplainedFailure()

        #expect(monitor.health == .failed(.permissionDenied))
    }

    /// An error that named its own cause is better information than an account
    /// status, so the refinement must leave it alone.
    @Test func refine_ExplainedFailure_IsUntouched() async {
        let monitor = makeMonitor(account: .noAccount)
        monitor.apply(.failed(.setup, error: ckError(.badContainer)))

        await monitor.refineUnexplainedFailure()

        #expect(monitor.health == .failed(.badContainer))
    }

    /// The check is asynchronous, so a retry can succeed while it is in flight.
    /// Its answer must not resurrect a failure the store has already recovered from.
    @Test func refine_AfterRecoveringInFlight_DoesNotOverwriteHealthy() async {
        let monitor = makeMonitor(account: .noAccount)
        monitor.apply(.failed(.setup, error: cocoaCloudKitError()))
        monitor.apply(.succeeded(.import))

        await monitor.refineUnexplainedFailure()

        #expect(monitor.health == .healthy)
    }

    /// The single construction point, so no test reaches the real
    /// `CloudKitAccountStatusProvider` — and with it a live `CKContainer` — by
    /// leaving an argument off.
    private func makeMonitor(
        activeStore: ModelContainerFactory.ActiveStore? = .mirrored,
        store: SyncStatusStore? = nil,
        account: CKAccountStatus = .available
    ) -> SyncHealthMonitor {
        SyncHealthMonitor(
            activeStore: activeStore,
            store: store ?? self.store(),
            account: StubAccountStatusProvider(status: account)
        )
    }

    private func store() -> SyncStatusStore {
        SyncStatusStore(defaults: defaults)
    }
}

// MARK: - Mocks

private nonisolated struct StubAccountStatusProvider: SyncAccountStatusProviding {
    let status: CKAccountStatus

    func accountStatus() async -> CKAccountStatus { status }
}
