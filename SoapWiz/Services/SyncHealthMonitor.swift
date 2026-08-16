import CloudKit
import CoreData
import Foundation
import OSLog

/// Watches CloudKit mirroring and publishes a state the UI can render.
///
/// Nothing in the app read the outcome of mirroring before this: the container
/// logged `Store is CloudKit-mirrored.` whether or not a single record ever left
/// the device, because `ModelContainer` init only validates the schema. Every
/// other failure — no account, a broken entitlement, a container that does not
/// exist server-side — surfaces asynchronously through
/// `NSPersistentCloudKitContainer.eventChangedNotification`, which is what this
/// listens to.
///
/// Held for the app's lifetime so the observer stays registered; mirroring
/// reports its first real verdict well after launch.
@MainActor
@Observable
final class SyncHealthMonitor {
    private(set) var health: SyncHealth
    private(set) var lastSuccessfulSync: Date?

    /// When a previous launch fell back to a local store and nothing has synced
    /// since, so the changes made in between may still be sitting on this device.
    ///
    /// Goes quiet once a later sync moves data, which is the earliest point the
    /// app can say mirroring is working again. Whether those specific rows ever
    /// export is a separate question, tracked in SW-100 — the persisted record
    /// outlives this property precisely so that work has something to act on.
    var unresolvedFallback: Date? {
        // A fallback happening right now is already the headline state; saying
        // it twice in the same row is noise.
        if case .localFallback = health { return nil }
        guard let fallback = store.lastLocalFallback,
              fallback.date > (lastSuccessfulSync ?? .distantPast) else { return nil }
        return fallback.date
    }

    /// None of these are state the UI observes; `@ObservationIgnored` keeps the
    /// macro from wrapping them, which also leaves `observer` a plain stored
    /// property that `nonisolated(unsafe)` can still apply to.
    @ObservationIgnored private let store: SyncStatusStore
    @ObservationIgnored private let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "sync")
    /// `nonisolated` so `deinit` can unregister it. Written once in `init` and
    /// read once in `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    @ObservationIgnored private let account: any SyncAccountStatusProviding
    @ObservationIgnored private var accountCheck: Task<Void, Never>?

    init(
        activeStore: ModelContainerFactory.ActiveStore?,
        store: SyncStatusStore = SyncStatusStore(),
        account: any SyncAccountStatusProviding = CloudKitAccountStatusProvider(
            containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier
        )
    ) {
        self.store = store
        self.account = account
        self.lastSuccessfulSync = store.lastSuccessfulSync
        switch activeStore {
        case .mirrored:
            // Not `healthy`: a store can mirror to a container that does not
            // exist, and claiming success before an event says so is the exact
            // silence this issue is about.
            self.health = .starting
        case .localFallback(let reason):
            self.health = .localFallback(reason: reason)
        case .notMirrored, nil:
            self.health = .notMirrored
        }
        observeMirroringEvents()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Folds one event into the published state. Separate from the notification
    /// plumbing so the interesting behaviour can be driven directly by a test —
    /// `NSPersistentCloudKitContainer.Event` cannot be constructed outside the
    /// framework.
    func apply(_ event: SyncEvent) {
        if event.isFinished, event.succeeded, event.movesData {
            let syncedAt = event.endDate ?? .now
            lastSuccessfulSync = syncedAt
            store.lastSuccessfulSync = syncedAt
        }

        if let error = event.error {
            // The full `NSError`, not `localizedDescription`: the latter collapses
            // to "Cocoa error 134400" and drops the domain, code and userInfo —
            // which is all there is to go on when no `CKError` is attached.
            let detail = "\(event.kind): \(error as NSError)"
            log.error("Mirroring event failed — \(detail, privacy: .public)")
        }

        let next = SyncHealth.reduce(health, with: event)
        guard next != health else { return }
        log.notice("Sync health: \(String(describing: next), privacy: .public)")
        health = next

        if case .failed(.other) = next {
            accountCheck?.cancel()
            accountCheck = Task { [weak self] in await self?.refineUnexplainedFailure() }
        }
    }

    /// Asks CloudKit what an unexplained failure actually was.
    ///
    /// Only runs for `other`, the verdict that means "the error named no cause".
    /// A failure that did name one is already better information than an account
    /// status can give.
    func refineUnexplainedFailure() async {
        let status = await account.accountStatus()
        // The state can have moved on while the check was in flight — a retry may
        // have succeeded — and only the unexplained verdict is ours to overwrite.
        guard case .failed(.other) = health else { return }

        switch status {
        case .noAccount:
            health = .signedOut
        case .restricted:
            health = .failed(.permissionDenied)
        case .temporarilyUnavailable:
            health = .failed(.offline)
        case .available, .couldNotDetermine:
            // Genuinely unexplained: there is an account, or CloudKit will not
            // say. Leave the error the event reported rather than invent a cause.
            break
        @unknown default:
            break
        }
        log.notice("Refined by account status: \(String(describing: self.health), privacy: .public)")
    }

    private func observeMirroringEvents() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let event = notification.cloudKitMirroringEvent else { return }
                self?.apply(event)
            }
        }
    }
}

private extension Notification {
    var cloudKitMirroringEvent: SyncEvent? {
        let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        guard let event = userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return nil }
        return SyncEvent(event)
    }
}

private extension SyncEvent {
    init(_ event: NSPersistentCloudKitContainer.Event) {
        self.init(
            kind: Kind(event.type),
            endDate: event.endDate,
            succeeded: event.succeeded,
            error: event.error
        )
    }
}

private extension SyncEvent.Kind {
    init(_ type: NSPersistentCloudKitContainer.EventType) {
        switch type {
        case .setup: self = .setup
        case .import: self = .import
        case .export: self = .export
        @unknown default: self = .unknown
        }
    }
}
