import CloudKit
import Foundation
import Testing
@testable import SoapWiz

@Suite
struct SyncErrorClassifierTests {

    @Test func classify_NotAuthenticated_IsSignedOutNotAFailure() {
        #expect(SyncErrorClassifier.classify(ckError(.notAuthenticated)) == .signedOut)
    }

    /// The shape mirroring actually delivers: a Cocoa error with the CloudKit
    /// cause buried underneath. Reading only the outer error would classify
    /// "not signed in" as an unknown fault and alarm every signed-out user.
    @Test func classify_NotAuthenticatedUnderCocoaError_IsSignedOut() {
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 134400,
            userInfo: [NSUnderlyingErrorKey: ckError(.notAuthenticated)]
        )
        #expect(SyncErrorClassifier.classify(wrapped) == .signedOut)
    }

    @Test func classify_NestedTwoLevelsDeep_StillFindsTheCloudKitCause() {
        let inner = NSError(
            domain: NSCocoaErrorDomain,
            code: 134400,
            userInfo: [NSUnderlyingErrorKey: ckError(.badContainer)]
        )
        let outer = NSError(
            domain: NSCocoaErrorDomain,
            code: 134060,
            userInfo: [NSUnderlyingErrorKey: inner]
        )
        #expect(SyncErrorClassifier.classify(outer) == .fault(.badContainer))
    }

    @Test func classify_BadContainer_IsAFault() {
        #expect(SyncErrorClassifier.classify(ckError(.badContainer)) == .fault(.badContainer))
    }

    @Test func classify_MissingEntitlement_IsAFault() {
        #expect(
            SyncErrorClassifier.classify(ckError(.missingEntitlement)) == .fault(.missingEntitlement)
        )
    }

    @Test func classify_QuotaExceeded_IsAFault() {
        #expect(SyncErrorClassifier.classify(ckError(.quotaExceeded)) == .fault(.quotaExceeded))
    }

    @Test(arguments: [
        CKError.Code.networkUnavailable,
        .networkFailure,
        .serviceUnavailable,
        .requestRateLimited,
        .zoneBusy,
        .accountTemporarilyUnavailable
    ])
    func classify_TemporaryConditions_AreTransient(code: CKError.Code) {
        #expect(SyncErrorClassifier.classify(ckError(code)) == .transient)
    }

    @Test func classify_NonCloudKitError_IsAnUnknownFault() {
        let error = NSError(domain: "pt.daphnia.test", code: 1)
        #expect(
            SyncErrorClassifier.classify(error) == .fault(.other(error.localizedDescription))
        )
    }
}

@Suite
struct SyncHealthReducerTests {

    @Test func reduce_EventStillRunningFromStarting_ShowsSyncing() {
        #expect(SyncHealth.reduce(.starting, with: .running(.import)) == .syncing)
    }

    /// A container that does not exist keeps kicking off fresh import attempts.
    /// Letting each one reset the row to "Syncing…" is exactly how a permanent
    /// fault hides behind a spinner.
    @Test func reduce_EventStillRunningAfterAFault_KeepsTheFault() {
        let current = SyncHealth.failed(.badContainer)
        #expect(SyncHealth.reduce(current, with: .running(.import)) == current)
    }

    @Test func reduce_SuccessfulImport_IsHealthy() {
        #expect(SyncHealth.reduce(.syncing, with: .succeeded(.import)) == .healthy)
    }

    /// Setup succeeding is the only proof a fresh launch gets that mirroring
    /// works at all, so it settles `starting` — but it moves no data, so it
    /// cannot overturn a fault that a real transfer already reported.
    @Test func reduce_SuccessfulSetupFromStarting_IsHealthy() {
        #expect(SyncHealth.reduce(.starting, with: .succeeded(.setup)) == .healthy)
    }

    @Test func reduce_SuccessfulSetupAfterAFault_KeepsTheFault() {
        let current = SyncHealth.failed(.quotaExceeded)
        #expect(SyncHealth.reduce(current, with: .succeeded(.setup)) == current)
    }

    @Test func reduce_FailedExportWithNoAccount_IsSignedOut() {
        let event = SyncEvent.failed(.export, error: ckError(.notAuthenticated))
        #expect(SyncHealth.reduce(.syncing, with: event) == .signedOut)
    }

    @Test func reduce_FailedExportWithBadContainer_IsAFault() {
        let event = SyncEvent.failed(.export, error: ckError(.badContainer))
        #expect(SyncHealth.reduce(.syncing, with: event) == .failed(.badContainer))
    }

    /// Losing the network with everything already copied up is not a problem,
    /// and reporting it as one trains people to ignore the row.
    @Test func reduce_NetworkErrorWhileHealthy_StaysHealthy() {
        let event = SyncEvent.failed(.export, error: ckError(.networkUnavailable))
        #expect(SyncHealth.reduce(.healthy, with: event) == .healthy)
    }

    @Test func reduce_NetworkErrorBeforeAnySync_ReportsOffline() {
        let event = SyncEvent.failed(.export, error: ckError(.networkUnavailable))
        #expect(SyncHealth.reduce(.starting, with: event) == .failed(.offline))
    }

    @Test func reduce_FailedEventWithNoError_IsStillAFailure() {
        let event = SyncEvent(kind: .export, endDate: .now, succeeded: false, error: nil)
        #expect(SyncHealth.reduce(.syncing, with: event) == .failed(.other(
            "iCloud reported a failure without saying why."
        )))
    }

    /// Nothing is mirroring in either state, so nothing an event says about
    /// mirroring can be about this store.
    @Test(arguments: [SyncHealth.notMirrored, .localFallback(reason: "no container")])
    func reduce_WhenNotMirroring_IgnoresEvents(current: SyncHealth) {
        #expect(SyncHealth.reduce(current, with: .succeeded(.import)) == current)
        #expect(
            SyncHealth.reduce(current, with: .failed(.export, error: ckError(.badContainer)))
                == current
        )
    }
}

@Suite
struct SyncHealthPresentationTests {

    /// The whole point of the issue: a signed-out user and a broken container
    /// must not read the same. One is a prompt, the other is a fault.
    @Test func severity_SignedOutVersusFault_AreDistinct() {
        #expect(SyncHealth.signedOut.severity == .actionable)
        #expect(SyncHealth.failed(.badContainer).severity == .fault)
        #expect(SyncHealth.signedOut.statusText != SyncHealth.failed(.badContainer).statusText)
    }

    @Test func severity_Healthy_IsNotAlarming() {
        #expect(SyncHealth.healthy.severity == .good)
    }

    /// Being offline is temporary and self-correcting; it belongs in the same
    /// visual register as "checking", not the one reserved for real faults.
    @Test func severity_Offline_IsInformational() {
        #expect(SyncHealth.failed(.offline).severity == .info)
    }

    @Test func settingsFooter_EveryState_ExplainsItself() {
        let states: [SyncHealth] = [
            .notMirrored,
            .localFallback(reason: "container unavailable"),
            .starting,
            .syncing,
            .signedOut,
            .healthy,
            .failed(.badContainer),
            .failed(.offline)
        ]
        for state in states {
            #expect(!state.settingsFooter.isEmpty, "\(state) has no footer")
            #expect(!state.statusText.isEmpty, "\(state) has no status text")
            #expect(!state.statusSymbol.isEmpty, "\(state) has no symbol")
        }
    }

    @Test func settingsFooter_LocalFallback_CarriesTheReason() {
        let footer = SyncHealth.localFallback(reason: "bad container").settingsFooter
        #expect(footer.contains("bad container"))
    }
}

// MARK: - Mocks

func ckError(_ code: CKError.Code) -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue)
}

/// What a failed setup event actually carries when there is no iCloud account:
/// no CloudKit code, no underlying error, no failure reason. Verified against
/// the simulator — Core Data logs the real reason but does not pass it on.
func cocoaCloudKitError() -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: 134400)
}

extension SyncEvent {
    /// An event CloudKit has posted but not finished — every event is posted
    /// twice, once on start and once on completion.
    static func running(_ kind: Kind) -> SyncEvent {
        SyncEvent(kind: kind, endDate: nil, succeeded: false, error: nil)
    }

    static func succeeded(_ kind: Kind, at endDate: Date = .now) -> SyncEvent {
        SyncEvent(kind: kind, endDate: endDate, succeeded: true, error: nil)
    }

    static func failed(_ kind: Kind, error: any Error, at endDate: Date = .now) -> SyncEvent {
        SyncEvent(kind: kind, endDate: endDate, succeeded: false, error: error)
    }
}
