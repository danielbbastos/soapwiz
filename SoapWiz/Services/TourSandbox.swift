import Foundation
import OSLog
import SwiftData

enum TourSandboxError: Error {
    /// The system refused the sandbox its own `UserDefaults` suite.
    case noThrowawayDefaults
}

private struct WeakContainer {
    weak var container: ModelContainer?
}

/// A separate, in-memory copy of the app for the onboarding tour: the ingredient
/// library plus `TourSample`, in a store of its own. The tour shows the real
/// tab interface on it, so nothing the user taps there can touch their data.
///
/// Everything else the interface would reach is isolated too. The store never
/// mirrors and never sets `ModelContainerFactory.activeStore`; the sync monitor
/// gets a throwaway `UserDefaults` suite, since its CloudKit event observer
/// listens to every container and would otherwise record the real last-sync
/// date as the sandbox's. Reminders and the lye acknowledgment are switched off
/// where they are read: see `isSandbox(_:)` and `\.isTourSandbox`.
///
/// Built in a few hundred milliseconds, so the tour can build it when it opens
/// rather than at launch. The spike measured about 170 ms on an iPhone simulator
/// (414 ms the first time) and 215 ms on an iPad Pro.
@MainActor
final class TourSandbox {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "tour")

    /// The containers of every sandbox alive. A set, since a second sandbox can
    /// be built while the first is still going away (the tour reopened during
    /// its dismiss animation). Weak with pointer identity, so a released sandbox
    /// needs no cleanup and nothing matches a container that has gone.
    ///
    /// Not an `NSHashTable`: it kept a released container alive, which is the
    /// one thing this must not do.
    private static var live: [WeakContainer] = []

    let container: ModelContainer
    let inventoryRows: InventoryRows
    let settings: SettingsState
    let navigation: AppNavigation
    let syncHealth: SyncHealthMonitor

    /// How long building took, from the empty store to the last row saved.
    let buildDuration: Duration

    /// Named once so `deinit`, which is `nonisolated`, can clear the suite.
    private let defaultsSuiteName: String

    /// Whether `context` belongs to a sandbox that is still alive.
    ///
    /// For code that has a context and no view environment, such as the reminder
    /// sync, which has many callers and must do nothing for any of them.
    static func isSandbox(_ context: ModelContext) -> Bool {
        live.contains { $0.container === context.container }
    }

    init(currencyCode: String, now: Date = .now) throws {
        let clock = ContinuousClock()
        let start = clock.now

        let suiteName = "pt.tachyon.SoapWiz.tour.\(UUID().uuidString)"
        // Never falls back to the standard defaults: the monitor would write the
        // real last-sync date there.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TourSandboxError.noThrowawayDefaults
        }
        defaultsSuiteName = suiteName

        container = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration(
                schema: ModelContainerFactory.schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = container.mainContext
        IngredientLibraryInstaller.installMissingLoggingFailure(in: context)
        _ = AppSettings.resolve(in: context)
        TourSample.insert(into: context, currencyCode: currencyCode, now: now)
        try context.save()

        // After the sample is in, so their first fetch already sees it.
        // The throwaway defaults, so an import event the real store posts can't
        // mark this device's first sync as done.
        inventoryRows = InventoryRows(
            context: context,
            firstImport: FirstImportRecord(defaults: defaults),
            syncStatus: SyncStatusStore(defaults: defaults)
        )
        settings = SettingsState(context: context)
        navigation = AppNavigation()
        syncHealth = SyncHealthMonitor(
            activeStore: .offlineByChoice,
            store: SyncStatusStore(defaults: defaults)
        )

        Self.live.removeAll { $0.container == nil }
        Self.live.append(WeakContainer(container: container))
        buildDuration = clock.now - start
        let formattedDuration = buildDuration.formatted(.units(allowed: [.milliseconds]))
        Self.log.notice("Tour sandbox built in \(formattedDuration, privacy: .public)")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
    }
}
