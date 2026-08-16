import CloudKit
import Foundation

/// What CloudKit mirroring is currently doing, as far as the app can tell.
///
/// Mirroring fails in two places and only one of them throws.
/// `ModelContainerFactory` catches a schema CloudKit rejects or a store file that
/// will not open; everything else lets `ModelContainer` init succeed and fails
/// later, asynchronously, inside the mirroring delegate. Both channels end up
/// here so the app has a single answer to "is my data leaving this device?".
///
/// `signedOut` is deliberately not a `failure`. It is the one state that fixes
/// itself the moment the user signs in, and wording it like a fault teaches
/// people to ignore the row that matters.
enum SyncHealth: Equatable {
    /// Built without the iCloud entitlement, so mirroring was never requested.
    case notMirrored
    /// Mirroring was requested and refused before the store opened.
    case localFallback(reason: String)
    /// Mirrored, but no event has arrived yet to say how it is going.
    case starting
    case syncing
    case signedOut
    case healthy
    case failed(SyncFailure)

    /// Short status for the Settings row.
    var statusText: String {
        switch self {
        case .notMirrored: "Off"
        case .localFallback: "Not Syncing"
        case .starting: "Checking…"
        case .syncing: "Syncing…"
        case .signedOut: "Not Signed In"
        case .healthy: "Synced"
        case .failed(let failure): failure.statusText
        }
    }

    var statusSymbol: String {
        switch self {
        case .notMirrored: "icloud.slash"
        case .localFallback: "exclamationmark.icloud.fill"
        case .starting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .signedOut: "person.crop.circle.badge.questionmark"
        case .healthy: "checkmark.icloud.fill"
        case .failed(let failure): failure.statusSymbol
        }
    }

    /// How loudly the row should read. A permanent fact about the build and a
    /// container that does not exist are both "not syncing", but only one of
    /// them is something going wrong.
    var severity: SyncSeverity {
        switch self {
        case .healthy: .good
        case .notMirrored, .starting, .syncing: .info
        case .signedOut: .actionable
        case .localFallback: .fault
        case .failed(let failure): failure.severity
        }
    }

    /// Whether this store is talking to CloudKit at all. False for the two states
    /// that were decided before the store opened and no event can change.
    var isMirroring: Bool {
        switch self {
        case .notMirrored, .localFallback: false
        case .starting, .syncing, .signedOut, .healthy, .failed: true
        }
    }

    /// The sentence under the Settings row. Every state gets one — a row that
    /// says only "Synced" leaves the user guessing what is synced and to where.
    var settingsFooter: String {
        switch self {
        case .notMirrored:
            "This build stores everything on this device only."
        case .localFallback(let reason):
            "SoapWiz could not reach iCloud when it started, so it is saving to this device only. "
                + "Your data is safe, but it is not being copied to your other devices. "
                + "Reopening the app will try again.\n\n\(reason)"
        case .starting:
            "Checking whether iCloud is available."
        case .syncing:
            "Copying changes to and from iCloud."
        case .signedOut:
            "Sign in to iCloud in the Settings app to keep your ingredients, recipes and "
                + "history on all your devices. Everything you add stays safe on this device "
                + "until you do."
        case .healthy:
            "Your ingredients, recipes and history are copied to iCloud and shared with your "
                + "other devices signed in to the same Apple Account."
        case .failed(let failure):
            failure.explanation
        }
    }
}

/// The reasons mirroring fails that the app can tell apart.
///
/// The split that matters is not the CloudKit error code but who can fix it:
/// `quotaExceeded` and `offline` are the user's to resolve, and the rest are
/// ours — a container that was never created server-side is a provisioning
/// mistake, and no amount of retrying will change it.
enum SyncFailure: Equatable {
    case badContainer
    case missingEntitlement
    case permissionDenied
    case quotaExceeded
    case offline
    case other(String)

    var statusText: String {
        switch self {
        case .badContainer, .missingEntitlement, .permissionDenied: "Unavailable"
        case .quotaExceeded: "iCloud Full"
        case .offline: "Offline"
        case .other: "Sync Failed"
        }
    }

    var statusSymbol: String {
        switch self {
        case .badContainer, .missingEntitlement, .permissionDenied: "xmark.icloud.fill"
        case .quotaExceeded: "exclamationmark.triangle.fill"
        case .offline: "wifi.slash"
        case .other: "exclamationmark.icloud.fill"
        }
    }

    var severity: SyncSeverity {
        switch self {
        case .offline: .info
        case .quotaExceeded: .actionable
        case .badContainer, .missingEntitlement, .permissionDenied, .other: .fault
        }
    }

    var explanation: String {
        switch self {
        case .badContainer, .missingEntitlement, .permissionDenied:
            "iCloud sync is not working in this version of SoapWiz. Your data is safe on this "
                + "device, but it is not being copied to your other devices. Use Export Data "
                + "below to keep your own copy."
        case .quotaExceeded:
            "There is no room left in your iCloud storage, so new changes are not being copied. "
                + "Free up space or upgrade your plan in the Settings app."
        case .offline:
            "SoapWiz cannot reach iCloud right now. It will catch up on its own once you are "
                + "back online."
        case .other(let description):
            "Something went wrong copying your data to iCloud. Your data is safe on this "
                + "device.\n\n\(description)"
        }
    }
}

/// How prominently a status should read, kept out of the view so it can be
/// asserted in tests rather than eyeballed.
enum SyncSeverity {
    case good
    case info
    case actionable
    case fault
}

/// One mirroring event, flattened out of `NSPersistentCloudKitContainer.Event`.
///
/// The framework type has no public initialiser, so reading it directly would
/// put every classification decision beyond the reach of a test. Translating at
/// the notification boundary keeps the interesting half — which errors are
/// benign, which are faults, what an in-flight event means — pure and testable.
struct SyncEvent {
    enum Kind {
        case setup
        /// Backticked because `import` is a keyword; the case is worth its real name.
        case `import`
        case export
        case unknown
    }

    var kind: Kind
    /// `nil` while the event is still running. CloudKit posts an event twice:
    /// once when it starts and once when it finishes.
    var endDate: Date?
    var succeeded: Bool
    var error: (any Error)?

    var isFinished: Bool { endDate != nil }

    /// Whether the event moved user data, as opposed to merely establishing that
    /// mirroring is possible. Only these count as a sync having happened.
    var movesData: Bool {
        switch kind {
        case .import, .export: true
        case .setup, .unknown: false
        }
    }
}

extension SyncHealth {
    /// Folds an event into the current state.
    ///
    /// Two rules keep the row from flapping, and both are the reason this is a
    /// reducer rather than a straight assignment:
    ///
    /// - Only finished events change the verdict. A failing container keeps
    ///   starting fresh import attempts, and letting each one reset the row to
    ///   "Syncing…" would hide a permanent fault behind a spinner.
    /// - A dropped connection does not undo a store that has already synced.
    ///   Being offline with everything already copied up is not a problem worth
    ///   reporting as one.
    static func reduce(_ current: SyncHealth, with event: SyncEvent) -> SyncHealth {
        // Nothing an event says about mirroring can be about a store that is
        // not mirroring.
        guard current.isMirroring else { return current }

        guard event.isFinished else {
            return current == .starting ? .syncing : current
        }

        if event.succeeded {
            // A successful setup is the only proof a fresh launch gets that
            // mirroring works at all, so it is allowed to settle `starting`.
            // After that only events that actually move data say anything new.
            return (event.movesData || current == .starting) ? .healthy : current
        }

        guard let error = event.error else {
            return .failed(.other("iCloud reported a failure without saying why."))
        }

        switch SyncErrorClassifier.classify(error) {
        case .signedOut:
            return .signedOut
        case .transient:
            return current == .healthy ? .healthy : .failed(.offline)
        case .fault(let failure):
            return .failed(failure)
        }
    }
}

/// Answers "is there an iCloud account to sync with?".
///
/// Needed because the error alone cannot say. Core Data knows perfectly well
/// that there is no account — its own log reads `Unable to initialize without an
/// iCloud account (CKAccountStatusNoAccount)` — but the error it hands to the
/// event arrives as a bare `NSCocoaErrorDomain 134400` with an empty userInfo
/// and no underlying `CKError`. Classifying that on its own would report the one
/// benign, self-correcting state as an unexplained fault.
protocol SyncAccountStatusProviding: Sendable {
    func accountStatus() async -> CKAccountStatus
}

nonisolated struct CloudKitAccountStatusProvider: SyncAccountStatusProviding {
    let containerIdentifier: String

    func accountStatus() async -> CKAccountStatus {
        do {
            return try await CKContainer(identifier: containerIdentifier).accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
}

/// Turns the error on a mirroring event into one of three verdicts.
enum SyncErrorClassifier {
    enum Verdict: Equatable {
        /// Benign and self-correcting: there is no iCloud account to sync with yet.
        case signedOut
        /// Real but temporary. Worth showing, never worth alarming about.
        case transient
        case fault(SyncFailure)
    }

    static func classify(_ error: any Error) -> Verdict {
        guard let code = cloudKitCode(in: error) else {
            return .fault(.other((error as NSError).localizedDescription))
        }
        switch code {
        case .notAuthenticated:
            return .signedOut
        case .accountTemporarilyUnavailable, .networkUnavailable, .networkFailure,
             .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .transient
        case .badContainer, .badDatabase:
            return .fault(.badContainer)
        case .missingEntitlement:
            return .fault(.missingEntitlement)
        case .permissionFailure, .managedAccountRestricted:
            return .fault(.permissionDenied)
        case .quotaExceeded:
            return .fault(.quotaExceeded)
        default:
            return .fault(.other((error as NSError).localizedDescription))
        }
    }

    /// Mirroring rarely hands over a `CKError` directly. The usual shape is a
    /// Cocoa error — `NSCocoaErrorDomain 134400` for the CloudKit integration —
    /// with the real cause buried under `NSUnderlyingErrorKey`, sometimes more
    /// than one level down.
    private static func cloudKitCode(in error: any Error) -> CKError.Code? {
        var next: NSError? = error as NSError
        while let current = next {
            if current.domain == CKErrorDomain,
               let code = CKError.Code(rawValue: current.code) {
                return code
            }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}
