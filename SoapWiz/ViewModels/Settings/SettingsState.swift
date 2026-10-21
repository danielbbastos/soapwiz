import CoreData
import Foundation
import OSLog
import SwiftData

/// The app-wide settings the root views read, kept apart from `@Query`.
///
/// A `@Query` on `AppSettings` in `ContentView` re-ran after every CloudKit
/// mirroring event even when nothing changed, which rebuilt the tab bar and
/// re-evaluated the whole inventory: about 225 ms on the main thread per import
/// on an iPad, against 77 ms without it. Here the two values those views need
/// are fetched by hand, and a property is only reassigned when its value differs,
/// so an unchanged refetch invalidates no view. `InventoryRows` has the full
/// rationale for the approach.
///
/// The settings are refetched when:
/// - this context saves an `AppSettings` record, straight away;
/// - a CloudKit import finishes and the store's history shows an `AppSettings`
///   record was written (`StoreHistoryCursor`);
/// - `refresh()` is called, which a reset does.
///
/// Unlike `InventoryRows`, nothing polls while an import is running: a setting
/// that arrives in a long first sync shows when the import finishes. Exports
/// never trigger anything.
@MainActor
@Observable
final class SettingsState {
    private(set) var currencyCode: String
    private(set) var tracksInventory: Bool
    private(set) var reminders: ReminderSettingsSnapshot

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let cursor: StoreHistoryCursor
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "settings")
    /// Set when the last refetch failed, so the next check retries even if the
    /// history shows nothing new.
    @ObservationIgnored private var needsReload = false
    /// How many `deferringRefreshes` calls are running; see `InventoryRows`.
    @ObservationIgnored private var deferralDepth = 0
    @ObservationIgnored private var refreshIsOwed = false
    /// `nonisolated` so `deinit` can unregister them. Written once in `init`
    /// and read once in `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    private static let settingsEntity = Schema.entityName(for: AppSettings.self)

    init(context: ModelContext, locale: Locale = .autoupdatingCurrent) {
        self.context = context
        self.locale = locale
        cursor = StoreHistoryCursor(context: context)
        currencyCode = AppSettings.currencyCode(from: [], locale: locale)
        tracksInventory = AppSettings.tracksInventory(from: [])
        reminders = ReminderSettingsSnapshot(records: [])
        reload()
        observe()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refetches the settings.
    func refresh() {
        // Everything written so far is about to be read, so the cursor needn't
        // report it again.
        _ = try? cursor.changesSinceLastCheck()
        refreshIsOwed = false
        reload()
    }

    /// Runs `body`, which saves several times, and refetches once afterwards
    /// if a save wrote an `AppSettings` record, even when `body` throws. Calls
    /// nest; only the outermost one refetches. `InventoryRows` has the
    /// rationale.
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

    /// Refetches when the store's history shows an `AppSettings` record was
    /// written since the last check, or can't be read, or when the last refetch
    /// failed. Returns whether it did.
    @discardableResult
    func refreshIfSettingsChanged() -> Bool {
        let changed = (try? cursor.changesSinceLastCheck())?
            .contains { $0.entityName == Self.settingsEntity } ?? true
        let shouldReload = changed || needsReload
        if shouldReload { reload() }
        return shouldReload
    }

    /// Reacts to one CloudKit mirroring event.
    func handle(_ event: SyncEvent) {
        guard event.kind == .import, event.isFinished else { return }
        refreshIfSettingsChanged()
    }

    private func reload() {
        let records: [AppSettings]
        do {
            records = try context.fetch(FetchDescriptor<AppSettings>())
        } catch {
            // The old values stay, and the history cursor has already moved
            // past whatever asked for this reload, so the next check retries.
            needsReload = true
            log.error("Settings fetch failed: \(error)")
            return
        }
        needsReload = false
        let code = AppSettings.currencyCode(from: records, locale: locale)
        if code != currencyCode { currencyCode = code }
        let tracks = AppSettings.tracksInventory(from: records)
        if tracks != tracksInventory { tracksInventory = tracks }
        let snapshot = ReminderSettingsSnapshot(records: records)
        if snapshot != reminders { reminders = snapshot }
    }

    private func refreshAfterSave() {
        if deferralDepth > 0 {
            refreshIsOwed = true
        } else {
            refresh()
        }
    }

    private func observe() {
        // No queue, so the block runs inside the save that posted it.
        observers.append(NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] notification in
            let names = InventoryRows.savedEntityNames(from: notification.userInfo)
            MainActor.assumeIsolated {
                // A skipped save leaves its history for the next
                // `refreshIfSettingsChanged()`, which filters it out too.
                if let names, !names.contains(Self.settingsEntity) { return }
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
