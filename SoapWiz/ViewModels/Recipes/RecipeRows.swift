import CoreData
import Foundation
import OSLog
import SwiftData

/// Every recipe, by name, kept apart from `@Query`.
///
/// Home is always on screen, so it can't hold a root `@Query`. `BatchRows` and
/// `InventoryRows` have the rationale; this follows `BatchRows` exactly, with
/// recipes and their ingredient lines as the watched entities.
@MainActor
@Observable
final class RecipeRows {
    private(set) var recipes: [Recipe] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let importTimeout: Duration
    @ObservationIgnored private let pruneInterval: Duration
    @ObservationIgnored private let fetchRecipes: @MainActor (ModelContext) throws -> [Recipe]
    @ObservationIgnored private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "recipes")
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private var deferralDepth = 0
    @ObservationIgnored private var refreshIsOwed = false
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    private static let watchedEntities: Set<String> = [
        Schema.entityName(for: Recipe.self),
        Schema.entityName(for: RecipeIngredient.self)
    ]

    private static func touchesRecipes(entityNames: some Sequence<String>) -> Bool {
        entityNames.contains { watchedEntities.contains($0) }
    }

    init(
        context: ModelContext,
        importTimeout: Duration = .seconds(120),
        pruneInterval: Duration = .seconds(1),
        fetchRecipes: @escaping @MainActor (ModelContext) throws -> [Recipe] = RecipeRows.fetchAll(in:)
    ) {
        self.context = context
        self.importTimeout = importTimeout
        self.pruneInterval = pruneInterval
        self.fetchRecipes = fetchRecipes
        cursor = StoreHistoryCursor(context: context)
        reload()
        observe()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        _ = try? cursor.changesSinceLastCheck()
        refreshIsOwed = false
        reload()
    }

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

    @discardableResult
    func refreshIfRecipesChanged() -> Bool {
        let changed = (try? cursor.changesSinceLastCheck())?
            .contains { Self.watchedEntities.contains($0.entityName) } ?? true
        let shouldReload = changed || needsReload
        if shouldReload { reload() }
        return shouldReload
    }

    func settlingMerge(_ body: () -> Void) {
        deferringRefreshes(body)
        refreshIfRecipesChanged()
    }

    func handle(_ event: SyncEvent) {
        guard event.kind == .import else { return }
        if event.isFinished {
            endImport()
            refreshIfRecipesChanged()
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
            self.refreshIfRecipesChanged()
        }
    }

    private func startPruning() {
        guard pruneTask == nil else { return }
        pruneTask = Task { [weak self, pruneInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pruneInterval)
                guard !Task.isCancelled, let self else { return }
                self.setRows(self.recipes)
            }
        }
    }

    private func endImport() {
        timeoutTask?.cancel()
        timeoutTask = nil
        pruneTask?.cancel()
        pruneTask = nil
    }

    /// Every recipe by name. Injected only so a test can count the fetches or make them fail.
    static func fetchAll(in context: ModelContext) throws -> [Recipe] {
        try context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\Recipe.name)]))
    }

    private func reload() {
        let fetched: [Recipe]
        do {
            fetched = try fetchRecipes(context)
        } catch {
            needsReload = true
            log.error("Recipe fetch failed: \(error)")
            return
        }
        needsReload = false
        setRows(fetched)
    }

    private func setRows(_ newRecipes: [Recipe]) {
        let live = newRecipes.filter { !$0.isDeleted && $0.modelContext != nil }
        if live != recipes { recipes = live }
    }

    private func refreshAfterSave() {
        if deferralDepth > 0 {
            refreshIsOwed = true
        } else {
            refresh()
        }
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] notification in
            let names = InventoryRows.savedEntityNames(from: notification.userInfo)
            MainActor.assumeIsolated {
                if let names, !Self.touchesRecipes(entityNames: names) { return }
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
