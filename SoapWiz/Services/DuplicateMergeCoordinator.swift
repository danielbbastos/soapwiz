import CoreData
import Foundation
import OSLog
import SwiftData

/// Decides *when* `DuplicateMerger` runs.
///
/// Duplicates do not exist at launch — they arrive later, when CloudKit imports
/// records another device created offline. A launch-only pass would therefore
/// leave them on screen for the whole session in which they appear, which is
/// exactly the session the user notices them and might add purchases to the wrong
/// copy. So the merge also runs when a CloudKit import finishes, and again
/// whenever the app returns to the foreground.
///
/// Import events rather than `.NSPersistentStoreRemoteChange`, which this used
/// to follow (SW-219). That notification fires for every save an import makes
/// and for the bookkeeping of every export, the merge's own saves included, so
/// a first sync ran a full pass on the main actor every second or so for as
/// long as it lasted, and the inventory stuttered under it. Only an import can
/// bring a duplicate in, and it reports when it is done.
///
/// Not `@Observable` — it publishes no state. Views hold it only to keep the
/// observer registered for the app's lifetime.
@MainActor
final class DuplicateMergeCoordinator {
    private let context: ModelContext
    private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "merge")
    private var pendingMerge: Task<Void, Never>?
    private var hasBeenActive = false
    /// `nonisolated` so `deinit` can unregister it. Written once in `init` and read
    /// once in `deinit`, never concurrently.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init(context: ModelContext) {
        self.context = context
        observeImports()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Whether `event` is one after which the store may hold new duplicates.
    /// A failed import still counts: it can stop part-way, after saving some of
    /// what it fetched.
    static func shouldMerge(after event: SyncEvent) -> Bool {
        event.kind == .import && event.isFinished
    }

    /// Runs the merge now, except on the app's first activation: launch has
    /// just merged, and nothing can have been imported in between.
    func appDidBecomeActive() {
        guard hasBeenActive else {
            hasBeenActive = true
            return
        }
        mergeNow()
    }

    /// Runs the merge now: on returning to the foreground, and once a burst of
    /// imports has gone quiet.
    ///
    /// Batch codes are settled on the same triggers, for the same reason: a
    /// batch without a code, or with one another device also handed out, only
    /// shows up once a sync brings it in.
    func mergeNow() {
        DuplicateMerger.mergeAllLoggingFailure(in: context)
        BatchCodeBackfill.fillMissingCodesLoggingFailure(in: context)
        BatchCodeDeduplicator.resolveLoggingFailure(in: context)
    }

    private func observeImports() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let event = notification.cloudKitMirroringEvent,
                      Self.shouldMerge(after: event) else { return }
                self?.scheduleDebouncedMerge()
            }
        }
    }

    /// A first sync can run several imports back to back, so wait for them to
    /// go quiet rather than scan and save between each.
    private func scheduleDebouncedMerge() {
        pendingMerge?.cancel()
        pendingMerge = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.log.notice("CloudKit import finished, merging duplicates.")
            self.mergeNow()
        }
    }
}
