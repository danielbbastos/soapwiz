import CoreData
import Foundation
import OSLog
import SwiftData

/// The inventory's ingredients, purchases and categories, kept apart from `@Query`.
///
/// This is the one place that doesn't read stored data with `@Query`, and the
/// reason is measured. SwiftData re-evaluates every `@Query` after each CloudKit
/// mirroring event, imports and exports, at start and at finish, even when no
/// row changed, because CloudKit writes its own bookkeeping to the store. On an
/// iPad with 238 ingredients and 409 purchases, one return to the foreground
/// with nothing changed spent about 256 ms in those two queries and another
/// 110 ms rebuilding the list. The same two fetches done by hand take about
/// 30 ms, and only when something relevant changed. The categories are a third
/// query the list view used to run on its own.
///
/// The rows are refetched when:
/// - this context saves something the inventory shows (an ingredient, purchase
///   or category), straight away, so an edit shows up the moment it is made.
///   Saves that touch only other entities, and saves by other contexts and by
///   CloudKit, don't count here;
/// - a duplicate merge ends (`settlingMerge`), which follows every import that
///   wrote anything. The store's history decides whether an ingredient,
///   purchase or category was written (`StoreHistoryCursor`), so imported
///   changes show even when the merge itself saved nothing;
/// - an import never finishes: `importTimeout` after it started, the history
///   is checked once;
/// - `refresh()` is called, which a reset does.
///
/// Nothing refetches while an import runs, nor when it finishes. A device
/// joining an existing account imports every library ingredient a second time
/// and only the merge that follows collapses them, so showing rows as they
/// arrive listed each ingredient twice for as long as the sync lasted.
/// `syncNotice` tells the view to say so instead. It is set for two kinds of
/// import, decided when the import begins: this device's first (it has never
/// completed one, see `FirstImportRecord`), and one after a long gap (its last
/// successful sync, from `SyncStatusStore`, is more than seven days old, or was
/// never recorded). Any other import is short and the list just updates once it
/// ends. Either way the notice appears only once the import has run for
/// `syncNoticeDelay`, so a qualifying import that ends quickly never flashes it.
///
/// Exports never trigger anything: they only send what this device has.
///
/// Deleted models are never handed out. Reading one can crash SwiftData, so
/// every refetch drops any row that is deleted or has left its context. With
/// no refetch during an import, a row another device deleted would stay in
/// the lists until the merge that follows, so about once a second while an
/// import runs the lists are pruned of such rows. The prune reads nothing from
/// the store and adds nothing, so rows still wait for the merge.
@MainActor
@Observable
final class InventoryRows {
    private(set) var ingredients: [Ingredient] = []
    private(set) var purchases: [IngredientPurchase] = []
    private(set) var categories: [IngredientCategory] = []

    /// The notice to show, once a first or catching-up import has been running
    /// for `syncNoticeDelay`; nil otherwise. A short import never sets it, so
    /// the notice doesn't flash on every return to the foreground.
    private(set) var syncNotice: SyncNotice?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let importTimeout: Duration
    @ObservationIgnored private let syncNoticeDelay: Duration
    @ObservationIgnored private let pruneInterval: Duration
    @ObservationIgnored private let firstImport: FirstImportRecord
    @ObservationIgnored private let syncStatus: SyncStatusStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetchRows: @MainActor (ModelContext) throws -> FetchedRows
    @ObservationIgnored private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "inventory")
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    /// Set when the last refetch failed, so the next check retries even if the
    /// history shows nothing new.
    @ObservationIgnored private var needsReload = false
    /// How many `deferringRefreshes` calls are running; saves only mark a
    /// refetch as owed while this is above zero.
    @ObservationIgnored private var deferralDepth = 0
    @ObservationIgnored private var refreshIsOwed = false
    /// `nonisolated` so `deinit` can unregister them. Written once in `init`
    /// and read once in `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    /// The three lists one refetch produces.
    struct FetchedRows {
        let ingredients: [Ingredient]
        let purchases: [IngredientPurchase]
        let categories: [IngredientCategory]
    }

    /// Entities whose changes can alter what the inventory shows.
    private static let watchedEntities: Set<String> = [
        Schema.entityName(for: Ingredient.self),
        Schema.entityName(for: IngredientPurchase.self),
        Schema.entityName(for: IngredientCategory.self)
    ]

    /// Whether a save that touched these entity names can alter what the
    /// inventory shows.
    static func touchesInventory(entityNames: some Sequence<String>) -> Bool {
        entityNames.contains { watchedEntities.contains($0) }
    }

    /// The entity names a `didSave` notification reports as inserted, updated
    /// or deleted, or nil when its `userInfo` is missing or can't be read.
    static func savedEntityNames(from userInfo: [AnyHashable: Any]?) -> Set<String>? {
        guard let userInfo else { return nil }
        let keys: [ModelContext.NotificationKey] = [
            .insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers
        ]
        var names: Set<String> = []
        var readAny = false
        for key in keys {
            guard let value = userInfo[key.rawValue] else { continue }
            guard let identifiers = value as? [PersistentIdentifier] else { return nil }
            readAny = true
            names.formUnion(identifiers.map(\.entityName))
        }
        return readAny ? names : nil
    }

    init(
        context: ModelContext,
        importTimeout: Duration = .seconds(120),
        syncNoticeDelay: Duration = .seconds(2),
        pruneInterval: Duration = .seconds(1),
        firstImport: FirstImportRecord = FirstImportRecord(),
        syncStatus: SyncStatusStore = SyncStatusStore(),
        now: @escaping () -> Date = { .now },
        fetchRows: @escaping @MainActor (ModelContext) throws -> FetchedRows = InventoryRows.fetchAll(in:)
    ) {
        self.context = context
        self.firstImport = firstImport
        self.syncStatus = syncStatus
        self.now = now
        self.fetchRows = fetchRows
        self.importTimeout = importTimeout
        self.syncNoticeDelay = syncNoticeDelay
        self.pruneInterval = pruneInterval
        cursor = StoreHistoryCursor(context: context)
        reload()
        observe()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refetches all three lists. Inside `deferringRefreshes` it also settles
    /// the refetch owed so far; a later save owes one again.
    func refresh() {
        // Everything written so far is about to be read, so the cursor needn't
        // report it again.
        _ = try? cursor.changesSinceLastCheck()
        refreshIsOwed = false
        reload()
    }

    /// Runs `body`, which saves several times, and refetches once afterwards
    /// instead of after every save: a duplicate merge saves two or three times
    /// and each refetch cost 45 to 60 ms. The refetch happens even when `body`
    /// throws, and only if a save that shows in the inventory happened.
    ///
    /// The "never render a deleted row" guarantee holds because `body` is
    /// synchronous on the main actor: no view can render before the refetch at
    /// the end. Calls nest; only the outermost one refetches.
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

    /// Refetches when the store's history shows an ingredient, purchase or
    /// category was written since the last check, or can't be read, or when the
    /// last refetch failed. Returns whether it did.
    @discardableResult
    func refreshIfInventoryChanged() -> Bool {
        let changed = (try? cursor.changesSinceLastCheck())?
            .contains { Self.watchedEntities.contains($0.entityName) } ?? true
        let shouldReload = changed || needsReload
        if shouldReload { reload() }
        return shouldReload
    }

    /// Runs `body`, a duplicate merge, then refetches if the history shows the
    /// inventory changed. The deferral's own refetch already moved the cursor
    /// past what the merge saved, so the check finds only what an import wrote
    /// and a merge that saved something costs one fetch, not two.
    func settlingMerge(_ body: () -> Void) {
        deferringRefreshes(body)
        refreshIfInventoryChanged()
    }

    /// Reacts to one CloudKit mirroring event. Only tracks the import for the
    /// notice and the timeout; the rows wait for the merge that follows.
    func handle(_ event: SyncEvent) {
        guard event.kind == .import else { return }
        if event.isFinished {
            if event.succeeded { firstImport.markCompleted() }
            endImport()
        } else {
            beginImport()
        }
    }

    private func beginImport() {
        startImportTimeout()
        startPruning()
        scheduleSyncNotice()
    }

    private func startImportTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, importTimeout] in
            try? await Task.sleep(for: importTimeout)
            guard !Task.isCancelled, let self else { return }
            self.endImport()
            self.refreshIfInventoryChanged()
        }
    }

    private func startPruning() {
        guard pruneTask == nil else { return }
        pruneTask = Task { [weak self, pruneInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pruneInterval)
                guard !Task.isCancelled, let self else { return }
                self.setRows(ingredients: self.ingredients, purchases: self.purchases, categories: self.categories)
            }
        }
    }

    private func scheduleSyncNotice() {
        guard noticeTask == nil, syncNotice == nil, let notice = noticeForImport() else { return }
        noticeTask = Task { [weak self, syncNoticeDelay] in
            try? await Task.sleep(for: syncNoticeDelay)
            guard !Task.isCancelled, let self else { return }
            self.noticeTask = nil
            self.syncNotice = notice
        }
    }

    /// Which notice an import that is just beginning earns, if any. Read when
    /// the import begins, before its own success is recorded: the monitor
    /// writes the last sync date only when an event finishes, so this never sees
    /// the import it is deciding about. A device that has completed an import
    /// but has no recorded sync date is treated as catching up, since nothing
    /// says it is current.
    private func noticeForImport() -> SyncNotice? {
        guard firstImport.isCompleted else { return .firstSync }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now()),
              let lastSync = syncStatus.lastSuccessfulSync else { return .catchingUp }
        return lastSync < cutoff ? .catchingUp : nil
    }

    private func endImport() {
        timeoutTask?.cancel()
        timeoutTask = nil
        noticeTask?.cancel()
        noticeTask = nil
        pruneTask?.cancel()
        pruneTask = nil
        if syncNotice != nil { syncNotice = nil }
    }

    /// Every fetch the inventory shows. Injected only so a test can count them or make them fail.
    static func fetchAll(in context: ModelContext) throws -> FetchedRows {
        FetchedRows(
            ingredients: try context.fetch(Ingredient.listDescriptor),
            purchases: try context.fetch(FetchDescriptor<IngredientPurchase>()),
            categories: try context.fetch(FetchDescriptor<IngredientCategory>(sortBy: [SortDescriptor(\.name)]))
        )
    }

    private func reload() {
        let fetched: FetchedRows
        do {
            fetched = try fetchRows(context)
        } catch {
            // The old rows stay, and the history cursor has already moved past
            // whatever asked for this reload, so the next check retries.
            needsReload = true
            log.error("Inventory fetch failed: \(error)")
            return
        }
        needsReload = false
        setRows(ingredients: fetched.ingredients, purchases: fetched.purchases, categories: fetched.categories)
    }

    /// Keeps the live rows of each list, assigning only what differs so an
    /// unchanged list invalidates no view.
    private func setRows(
        ingredients newIngredients: [Ingredient],
        purchases newPurchases: [IngredientPurchase],
        categories newCategories: [IngredientCategory]
    ) {
        let liveIngredients = Self.live(newIngredients)
        if liveIngredients != ingredients { ingredients = liveIngredients }
        let livePurchases = Self.live(newPurchases)
        if livePurchases != purchases { purchases = livePurchases }
        let liveCategories = Self.live(newCategories)
        if liveCategories != categories { categories = liveCategories }
    }

    private static func live<Model: PersistentModel>(_ models: [Model]) -> [Model] {
        models.filter { !$0.isDeleted && $0.modelContext != nil }
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
        ) { [weak self] notification in
            let names = Self.savedEntityNames(from: notification.userInfo)
            MainActor.assumeIsolated {
                // A skipped save leaves its history for the next
                // `refreshIfInventoryChanged()`, which filters it out too.
                if let names, !Self.touchesInventory(entityNames: names) { return }
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
