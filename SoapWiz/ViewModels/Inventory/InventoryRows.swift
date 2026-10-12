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
/// - a CloudKit import finishes and the store's history shows an ingredient,
///   purchase or category was written (`StoreHistoryCursor`);
/// - an import is still running, checked the same way about once a second, so a
///   long first sync fills the list as it goes. The polling stops when the
///   import finishes, or after `maxPollDuration` if no finish event ever
///   arrives, and a later import start begins it again;
/// - `refresh()` is called, which a duplicate merge and a reset do.
///
/// Exports never trigger anything: they only send what this device has.
///
/// Deleted models are never handed out. Reading one can crash SwiftData, so
/// every refetch drops any row that is deleted or has left its context.
@MainActor
@Observable
final class InventoryRows {
    private(set) var ingredients: [Ingredient] = []
    private(set) var purchases: [IngredientPurchase] = []
    private(set) var categories: [IngredientCategory] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let maxPollDuration: Duration
    @ObservationIgnored private let fetchRows: @MainActor (ModelContext) throws -> FetchedRows
    @ObservationIgnored private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "inventory")
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Set when the last refetch failed, so the next check retries even if the
    /// history shows nothing new.
    @ObservationIgnored private var needsReload = false
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
        pollInterval: Duration = .seconds(1),
        maxPollDuration: Duration = .seconds(120),
        fetchRows: @escaping @MainActor (ModelContext) throws -> FetchedRows = InventoryRows.fetchAll(in:)
    ) {
        self.context = context
        self.fetchRows = fetchRows
        self.pollInterval = pollInterval
        self.maxPollDuration = maxPollDuration
        cursor = StoreHistoryCursor(context: context)
        reload()
        observe()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refetches all three lists.
    func refresh() {
        // Everything written so far is about to be read, so the cursor needn't
        // report it again.
        _ = try? cursor.changesSinceLastCheck()
        reload()
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

    /// Reacts to one CloudKit mirroring event.
    func handle(_ event: SyncEvent) {
        guard event.kind == .import else { return }
        if event.isFinished {
            polling?.cancel()
            polling = nil
            refreshIfInventoryChanged()
        } else if polling == nil {
            startPolling()
        }
    }

    private func startPolling() {
        polling = Task { [weak self, pollInterval, maxPollDuration] in
            let deadline = ContinuousClock.now.advanced(by: maxPollDuration)
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refreshIfInventoryChanged()
                if ContinuousClock.now >= deadline {
                    self.polling = nil
                    return
                }
            }
        }
    }

    /// Every fetch the inventory shows. Injected only so a test can make them fail.
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
        let liveIngredients = Self.live(fetched.ingredients)
        if liveIngredients != ingredients { ingredients = liveIngredients }
        let livePurchases = Self.live(fetched.purchases)
        if livePurchases != purchases { purchases = livePurchases }
        let liveCategories = Self.live(fetched.categories)
        if liveCategories != categories { categories = liveCategories }
    }

    private static func live<Model: PersistentModel>(_ models: [Model]) -> [Model] {
        models.filter { !$0.isDeleted && $0.modelContext != nil }
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
                self?.refresh()
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
