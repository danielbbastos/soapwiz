import CoreData
import Foundation
import OSLog
import SwiftData

/// A list of models kept apart from `@Query`.
///
/// Home is always on screen, so it can't hold a root `@Query`: SwiftData
/// re-evaluates every `@Query` after each CloudKit mirroring event, even when no
/// row changed. `InventoryRows` has the measured rationale for fetching by hand
/// instead.
///
/// The rows are refetched when:
/// - this context saves a watched entity, straight away, so an edit shows up
///   the moment it is made. Saves that touch only other entities, and saves by
///   other contexts and by CloudKit, don't count here;
/// - a CloudKit import finishes and the store's history shows a watched entity
///   was written (`StoreHistoryCursor`), or can't be read;
/// - an import never finishes: `importTimeout` after it started, the history is
///   checked once;
/// - a duplicate merge ends (`settlingMerge`), which can save watched entities
///   several times;
/// - `refresh()` is called, which a reset does.
///
/// Unlike `InventoryRows`, an import finishing doesn't wait for the merge: the
/// rows can refresh as soon as the import is done, as `SettingsState` does.
/// Nothing refetches while an import runs. Exports never trigger anything.
///
/// Deleted models are never handed out. Reading one can crash SwiftData, so
/// every refetch drops any row that is deleted or has left its context. With no
/// refetch during an import, a model another device deleted would stay in the
/// list until it ends, so about once a second while an import runs the list is
/// pruned of such rows. The prune reads nothing from the store and adds nothing.
@MainActor
@Observable
final class ModelRows<Model: PersistentModel> {
    private(set) var rows: [Model] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let importTimeout: Duration
    @ObservationIgnored private let pruneInterval: Duration
    @ObservationIgnored private let fetch: @MainActor (ModelContext) throws -> [Model]
    /// Entities whose changes can alter what the rows show.
    @ObservationIgnored private let watchedEntities: Set<String>
    @ObservationIgnored private let log: Logger
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    /// Set when the last refetch failed, so the next check retries even if the
    /// history shows nothing new.
    @ObservationIgnored private var needsReload = false
    /// How many `deferringRefreshes` calls are running; see `InventoryRows`.
    @ObservationIgnored private var deferralDepth = 0
    @ObservationIgnored private var refreshIsOwed = false
    /// `nonisolated` so `deinit` can unregister them. Written once in `init`
    /// and read once in `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    init(
        context: ModelContext,
        watchedEntities: Set<String>,
        logCategory: String,
        importTimeout: Duration = .seconds(120),
        pruneInterval: Duration = .seconds(1),
        fetch: @escaping @MainActor (ModelContext) throws -> [Model]
    ) {
        self.context = context
        self.watchedEntities = watchedEntities
        self.importTimeout = importTimeout
        self.pruneInterval = pruneInterval
        self.fetch = fetch
        log = Logger(subsystem: "pt.tachyon.SoapWiz", category: logCategory)
        cursor = StoreHistoryCursor(context: context)
        reload()
        observe()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refetches the rows. Inside `deferringRefreshes` it also settles the
    /// refetch owed so far; a later save owes one again.
    func refresh() {
        // Everything written so far is about to be read, so the cursor needn't
        // report it again.
        _ = try? cursor.changesSinceLastCheck()
        refreshIsOwed = false
        reload()
    }

    /// Runs `body`, which saves several times, and refetches once afterwards
    /// instead of after every save, and only if a save that shows in the rows
    /// happened. The refetch happens even when `body` throws. Calls nest; only
    /// the outermost one refetches. `InventoryRows` has the rationale.
    func deferringRefreshes<Result>(_ body: () throws -> Result) rethrows -> Result {
        deferralDepth += 1
        defer {
            deferralDepth -= 1
            if deferralDepth == 0, refreshIsOwed {
                refresh()
            }
        }
        return try body()
    }

    /// Refetches when the store's history shows a watched entity was written
    /// since the last check, or can't be read, or when the last refetch failed.
    /// Returns whether it did.
    @discardableResult
    func refreshIfChanged() -> Bool {
        let changed = (try? cursor.changesSinceLastCheck())?
            .contains { watchedEntities.contains($0.entityName) } ?? true
        let shouldReload = changed || needsReload
        if shouldReload { reload() }
        return shouldReload
    }

    /// Runs `body`, a duplicate merge, then refetches if the history shows the
    /// rows changed. The deferral's own refetch already moved the cursor past
    /// what the merge saved, so the check finds only what an import wrote.
    func settlingMerge(_ body: () -> Void) {
        deferringRefreshes(body)
        refreshIfChanged()
    }

    /// Reacts to one CloudKit mirroring event. Only imports count: the rows are
    /// refreshed when one finishes, and pruned while one runs.
    func handle(_ event: SyncEvent) {
        guard event.kind == .import else { return }
        if event.isFinished {
            endImport()
            refreshIfChanged()
        } else {
            beginImport()
        }
    }

    private func beginImport() {
        startImportTimeout()
        startPruning()
    }

    private func startImportTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, importTimeout] in
            try? await Task.sleep(for: importTimeout)
            guard !Task.isCancelled, let self else { return }
            self.endImport()
            self.refreshIfChanged()
        }
    }

    private func startPruning() {
        guard pruneTask == nil else { return }
        pruneTask = Task { [weak self, pruneInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pruneInterval)
                guard !Task.isCancelled, let self else { return }
                self.setRows(self.rows)
            }
        }
    }

    private func endImport() {
        timeoutTask?.cancel()
        timeoutTask = nil
        pruneTask?.cancel()
        pruneTask = nil
    }

    private func reload() {
        let fetched: [Model]
        do {
            fetched = try fetch(context)
        } catch {
            // The old rows stay, and the history cursor has already moved past
            // whatever asked for this reload, so the next check retries.
            needsReload = true
            log.error("\(String(describing: Model.self)) fetch failed: \(error)")
            return
        }
        needsReload = false
        setRows(fetched)
    }

    /// Keeps the live rows, assigning only when they differ so an unchanged
    /// list invalidates no view.
    private func setRows(_ newRows: [Model]) {
        let live = newRows.filter { !$0.isDeleted && $0.modelContext != nil }
        if live != rows { rows = live }
    }

    private func refreshAfterSave() {
        if deferralDepth > 0 {
            refreshIsOwed = true
        } else {
            refresh()
        }
    }

    private func observe() {
        // No queue, so the block runs inside the save that posted it: a view
        // never gets to render a deleted row in between.
        observers.append(NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self, watchedEntities] notification in
            let names = InventoryRows.savedEntityNames(from: notification.userInfo)
            MainActor.assumeIsolated {
                // A skipped save leaves its history for the next
                // `refreshIfChanged()`, which filters it out too.
                if let names, !names.contains(where: { watchedEntities.contains($0) }) { return }
                self?.refreshAfterSave()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let event = notification.cloudKitMirroringEvent else { return }
                self?.handle(event)
            }
        })
    }
}
