import SwiftUI
import SwiftData

/// Owns the destructive half of the import flow: staging a decoded backup, tearing
/// the interface down, wiping and rebuilding the store, then handing the outcome back.
///
/// The teardown is the whole point. A restore deletes every model in the store, and
/// any screen still mounted at that moment is holding references to models that are
/// about to be deleted — a pushed recipe detail keeps `Ingredient`s alive through its
/// view model, and the navigation paths retain the models they pushed. Those screens
/// get re-evaluated as the wipe lands and read attributes off detached objects, which
/// traps. So the app switches to a placeholder first and only then touches the store.
@Observable
@MainActor
final class RestoreCoordinator {
    enum Phase: Equatable {
        case idle
        case restoring
    }

    /// A decoded, validated backup awaiting the user's confirmation to replace.
    var pendingImport: BackupData?

    /// `.restoring` means the interface has been torn down and the store is being
    /// rebuilt; the placeholder on screen is what drives `perform(in:)`.
    private(set) var phase: Phase = .idle

    /// Bumped after every restore so the rebuilt interface cannot reuse view state
    /// left over from before the wipe.
    private(set) var generation = 0

    /// Set once a restore replaced existing data, so the user can be told an undo
    /// exists. `nil` when the store was empty beforehand.
    var rollbackFile: ExportFile?

    /// Set when the user asks to save the rollback file, which presents the share
    /// sheet. Kept apart from `rollbackFile` so "an undo exists" and "show me the
    /// share sheet" stay distinct states.
    var rollbackShare: ExportFile?

    /// User-facing error message for the restore itself.
    var errorMessage: String?

    /// How long the placeholder waits before touching the store. Releasing the view
    /// state is synchronous, but the UIKit layer underneath it is not — navigation
    /// controllers hold their pushed controllers until they are themselves gone, and
    /// hosting views drain with the autorelease pool at the end of the runloop turn.
    /// Sleeping (rather than yielding) is what actually ends that turn.
    var settleDelay: Duration = .milliseconds(50)

    /// Where the rollback file is written. `nil` means Documents.
    var rollbackDirectory: URL?

    private static let rollbackPrefix = "SoapWiz-Rollback-"

    private var stagedBackup: BackupData?

    // MARK: - Staging

    func stage(_ backup: BackupData) {
        pendingImport = backup
    }

    func cancel() {
        pendingImport = nil
    }

    /// Accepts the pending import: clears the navigation state that outlives the
    /// teardown and switches to the restoring phase, which takes the interface down.
    ///
    /// `AppNavigation` is owned above the rebuilt tree and so survives it. Its
    /// `historyPath` can hold a `Batch` the wipe is about to delete, and a rebuilt
    /// history tab would push straight back onto that detached model; `pendingRecipeSeed`
    /// holds `Ingredient`s the same way. The tab-local paths need no such handling —
    /// they are discarded along with the views that own them.
    func begin(navigation: AppNavigation) {
        guard let backup = pendingImport else { return }
        pendingImport = nil
        stagedBackup = backup

        navigation.historyPath = NavigationPath()
        navigation.pendingRecipeSeed = nil

        phase = .restoring
    }

    // MARK: - Restoring

    /// Runs the restore. Called from the placeholder's `.task`, which is what
    /// guarantees the interface holding the old models is already gone.
    func perform(in context: ModelContext) async {
        guard phase == .restoring, let backup = stagedBackup else { return }
        stagedBackup = nil

        await Task.yield()
        if settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
        }

        let rollback: URL?
        do {
            rollback = try writeRollback(from: context)
        } catch {
            // Fail closed. The whole point of the rollback is that a mis-tap is
            // recoverable; restoring without one silently removes that guarantee
            // at the exact moment the user is relying on it.
            errorMessage = "Couldn’t save a copy of your current data, so nothing was "
                + "changed. Export a backup first, then try importing again."
            finish()
            return
        }

        do {
            try BackupService.restore(backup, into: context)
            rollbackFile = rollback.map(ExportFile.init(url:))
            // Only once the new snapshot is safely written and the restore has
            // actually happened. Pruning any earlier would trade a rollback the
            // user still has for one they might not get.
            pruneRollbacks(keeping: rollback)
        } catch let error as BackupError {
            errorMessage = error.errorDescription
            discardRollback(rollback)
        } catch {
            errorMessage = "Couldn’t restore this backup."
            discardRollback(rollback)
        }

        // The scheduled expiry notifications refer to purchases that no longer exist.
        // Before `finish()`, not after: leaving `.restoring` takes the placeholder off
        // screen, and this runs inside the task that placeholder owns — SwiftUI would
        // cancel it mid-flight and the restored purchases could end up with no
        // notifications at all, silently.
        await NotificationService.syncIfEnabled(modelContext: context)

        finish()
    }

    /// Rebuilds the interface, whichever way the restore went. A failed import must
    /// not strand the user on the restoring placeholder.
    private func finish() {
        generation += 1
        phase = .idle
    }

    /// Snapshots the current store to a file so a restore can be undone. Returns
    /// `nil` when the store is empty — there is nothing to roll back to, and an
    /// empty rollback file is worse than none.
    ///
    /// Written to Documents rather than the temporary directory the export flow
    /// uses: an export goes straight into the share sheet, but a rollback has to
    /// still be there later, after the user realises they imported the wrong file.
    private func writeRollback(from context: ModelContext) throws -> URL? {
        let backup = try BackupService.makeBackup(from: context)
        guard !backup.isEmpty else { return nil }

        let data = try BackupService.encode(backup)
        let url = try rollbackDirectoryURL()
            .appendingPathComponent(Self.rollbackFileName(for: backup.exportedAt))
        try data.write(to: url, options: .atomic)
        return url
    }

    private func rollbackDirectoryURL() throws -> URL {
        if let rollbackDirectory { return rollbackDirectory }
        return try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    /// Drops the snapshot written for a restore that then failed. `BackupService.restore`
    /// rolls the context back, so it describes a store that was never replaced — keeping
    /// it would leave a file in Documents the user was never told about.
    private func discardRollback(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Leaves `kept` as the only rollback on disk. One import's worth of undo is the
    /// whole promise; without this every confirmed import would add a full-store
    /// snapshot to Documents forever, and older ones describe a store the user has
    /// since replaced anyway.
    ///
    /// Nothing is pruned when there is no new snapshot to keep. A restore over an
    /// empty store writes no rollback, and the earlier ones are then the only way
    /// back to data that nothing has replaced.
    private func pruneRollbacks(keeping kept: URL?) {
        guard let kept else { return }
        guard let directory = try? rollbackDirectoryURL() else { return }
        let existing = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in existing ?? [] where url != kept && Self.isRollbackFile(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func isRollbackFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(rollbackPrefix) && url.pathExtension == "json"
    }

    /// Rollback file name, e.g. `SoapWiz-Rollback-2026-06-25-143000.json`. Named
    /// distinctly from an export so the two aren't confused in a file list.
    static func rollbackFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(rollbackPrefix)\(formatter.string(from: date)).json"
    }
}
