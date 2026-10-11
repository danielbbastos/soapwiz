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
/// copy. So the merge also runs when a CloudKit import finishes.
///
/// Returning to the foreground is not a trigger. Duplicates only arrive through
/// imports, and the import that runs on activation (including one that ran while
/// the app was suspended) reports when it is done, so the merge then runs once
/// rather than once on activation and again a second later.
///
/// Import events rather than `.NSPersistentStoreRemoteChange`, which this used
/// to follow (SW-219). That notification fires for every save an import makes
/// and for the bookkeeping of every export, the merge's own saves included, so
/// a first sync ran a full pass on the main actor every second or so for as
/// long as it lasted, and the inventory stuttered under it. Only an import can
/// bring a duplicate in, and it reports when it is done.
///
/// An import that wrote nothing doesn't merge either. Most imports are empty:
/// CloudKit reports one on every return to the foreground, and the pass costs
/// 77 to 105 ms of main-actor time even when there is nothing to merge. The
/// store's history says whether an import changed anything (see
/// `StoreHistoryCursor`); when it can't be read, the merge runs as it would
/// have. A skipped import never cancels a merge an earlier import in the same
/// debounce window asked for.
///
/// Not `@Observable` — it publishes no state. Views hold it only to keep the
/// observer registered for the app's lifetime.
@MainActor
final class DuplicateMergeCoordinator {
    private let context: ModelContext
    private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "merge")
    private let cursor: StoreHistoryCursor
    private let debounce: Duration
    private var pendingMerge: Task<Void, Never>?
    /// `nonisolated` so `deinit` can unregister it. Written once in `init` and read
    /// once in `deinit`, never concurrently.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init(context: ModelContext, debounce: Duration = .milliseconds(500)) {
        self.context = context
        self.debounce = debounce
        cursor = StoreHistoryCursor(context: context)
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

    /// Whether a finished import should lead to a merge, given how many changes
    /// the store's history shows since the last one. `nil` means the history
    /// couldn't be read, so anything may have changed.
    static func shouldMerge(historyChangeCount: Int?) -> Bool {
        guard let historyChangeCount else { return true }
        return historyChangeCount > 0
    }

    /// Runs the merge now: once a burst of imports has gone quiet.
    ///
    /// Batch codes are settled on the same trigger, for the same reason: a
    /// batch without a code, or with one another device also handed out, only
    /// shows up once a sync brings it in.
    func mergeNow(trigger: String = "manual") {
        let signposter = Signposts.foreground
        let state = signposter.beginInterval("Merge", "\(trigger, privacy: .public)")
        defer { signposter.endInterval("Merge", state) }
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
                Signposts.foreground.emitEvent("CloudKit import finished")
                self?.importFinished()
            }
        }
    }

    /// Asks the history what the import wrote, and schedules a merge unless it
    /// wrote nothing. Always asks, even while a merge is pending, so the cursor
    /// advances with every import.
    func importFinished() {
        let changeCount = try? cursor.changesSinceLastCheck().count
        guard Self.shouldMerge(historyChangeCount: changeCount) else { return }
        scheduleDebouncedMerge()
    }

    /// A first sync can run several imports back to back, so wait for them to
    /// go quiet rather than scan and save between each.
    private func scheduleDebouncedMerge() {
        pendingMerge?.cancel()
        pendingMerge = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.log.notice("CloudKit import finished, merging duplicates.")
            self.mergeNow(trigger: "import finished")
        }
    }
}
