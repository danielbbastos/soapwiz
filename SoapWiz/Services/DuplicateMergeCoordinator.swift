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
/// copy. So the merge also runs when the store reports a remote change, and again
/// whenever the app returns to the foreground.
/// Not `@Observable` — it publishes no state. Views hold it only to keep the
/// remote-change observer registered for the app's lifetime.
@MainActor
final class DuplicateMergeCoordinator {
    private let context: ModelContext
    private let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "merge")
    private var pendingMerge: Task<Void, Never>?
    /// `nonisolated` so `deinit` can unregister it. Written once in `init` and read
    /// once in `deinit`, never concurrently.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init(context: ModelContext) {
        self.context = context
        observeRemoteChanges()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Runs the merge now. Used at launch and on foreground, where there is no
    /// burst to coalesce.
    func mergeNow() {
        DuplicateMerger.mergeAllLoggingFailure(in: context)
    }

    /// `.NSPersistentStoreRemoteChange` is public Core Data API, but Apple
    /// documents no SwiftData contract for it. The `.notice` log below is how a
    /// device build confirms it actually fires; if it never does, the launch and
    /// foreground triggers still bound how long duplicates can linger.
    private func observeRemoteChanges() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleDebouncedMerge()
            }
        }
    }

    /// CloudKit posts remote-change notifications in bursts while an import runs.
    /// Merging on each one would repeatedly scan and save mid-import, so wait for
    /// the burst to go quiet first.
    private func scheduleDebouncedMerge() {
        pendingMerge?.cancel()
        pendingMerge = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.log.notice("Remote store change settled, merging duplicates.")
            self.mergeNow()
        }
    }
}
