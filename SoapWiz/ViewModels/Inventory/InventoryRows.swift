import CoreData
import Foundation
import SwiftData

/// The inventory's ingredients and purchases, kept apart from `@Query`.
///
/// This is the one place that doesn't read stored data with `@Query`, and the
/// reason is measured. SwiftData re-evaluates every `@Query` after each CloudKit
/// mirroring event, imports and exports, at start and at finish, even when no
/// row changed, because CloudKit writes its own bookkeeping to the store. On an
/// iPad with 238 ingredients and 409 purchases, one return to the foreground
/// with nothing changed spent about 256 ms in those two queries and another
/// 110 ms rebuilding the list. The same two fetches done by hand take about
/// 30 ms, and only when something relevant changed.
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

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let maxPollDuration: Duration
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// `nonisolated` so `deinit` can unregister them. Written once in `init`
    /// and read once in `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

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
        maxPollDuration: Duration = .seconds(120)
    ) {
        self.context = context
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

    /// Refetches both lists.
    func refresh() {
        // Everything written so far is about to be read, so the cursor needn't
        // report it again.
        _ = try? cursor.changesSinceLastCheck()
        reload()
    }

    /// Refetches when the store's history shows an ingredient, purchase or
    /// category was written since the last check, or can't be read. Returns
    /// whether it did.
    @discardableResult
    func refreshIfInventoryChanged() -> Bool {
        let changed = (try? cursor.changesSinceLastCheck())?
            .contains { Self.watchedEntities.contains($0.entityName) } ?? true
        if changed { reload() }
        return changed
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

    private func reload() {
        if let fetched = try? context.fetch(Ingredient.listDescriptor) {
            let live = Self.live(fetched)
            if live != ingredients { ingredients = live }
        }
        if let fetched = try? context.fetch(FetchDescriptor<IngredientPurchase>()) {
            let live = Self.live(fetched)
            if live != purchases { purchases = live }
        }
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
