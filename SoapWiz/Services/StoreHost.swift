import Foundation
import SwiftData

/// Owns the app's `ModelContainer` and everything tied to it, and erases the
/// store when the user resets everything.
///
/// A reset needs the interface gone first, for the reason `RestoreCoordinator`
/// gives: a screen still on screen holds models, and reads them after they are
/// deleted. So `requestReset()` only records the request; the app then shows a
/// placeholder, and the placeholder's task calls `performReset()`.
///
/// Turning sync on or off takes effect on the next launch, not here. Opening a
/// second container in the same session left open screens unaware of
/// relationship changes — a purchase added to an ingredient on screen didn't
/// show until the screen was reopened — so the store is only ever opened once.
@MainActor
@Observable
final class StoreHost {
    enum Phase: Equatable {
        case ready
        case resetting
    }

    private(set) var phase: Phase = .ready

    let container: ModelContainer
    let syncHealth: SyncHealthMonitor

    /// Whether this launch opened the store without iCloud.
    let isOffline: Bool

    /// Whether the user wants sync off, which the next launch applies.
    var prefersOffline: Bool {
        didSet { preference.usesOffline = prefersOffline }
    }

    /// The saved choice differs from the store this launch opened.
    var needsRelaunch: Bool { prefersOffline != isOffline }

    /// Bumped after every reset so the rebuilt interface starts fresh.
    private(set) var generation = 0

    /// Set when a reset failed.
    var errorMessage: String?

    @ObservationIgnored private let mergeCoordinator: DuplicateMergeCoordinator
    @ObservationIgnored private let preference: SyncPreference

    /// How long the placeholder waits before touching the store; see
    /// `RestoreCoordinator.settleDelay`.
    @ObservationIgnored var settleDelay: Duration = .milliseconds(50)

    init(preference: SyncPreference = SyncPreference()) {
        self.preference = preference
        let offline = preference.usesOffline
        isOffline = offline
        prefersOffline = offline

        let container = ModelContainerFactory.makeProduction(offline: offline)
        // Straight after the store opens, so its import observer is registered
        // before the launch merge below: an import that finished in between
        // would otherwise go unmerged until the next one. Built before the
        // scene's first activation, which it has to see in order to skip it.
        // Held for the app's lifetime; CloudKit imports duplicates long after
        // launch.
        mergeCoordinator = DuplicateMergeCoordinator(context: container.mainContext)
        Self.prepare(container.mainContext)
        self.container = container
        // After `makeProduction()`, which records which store it opened.
        syncHealth = SyncHealthMonitor(activeStore: ModelContainerFactory.activeStore)
    }

    func requestReset() {
        guard phase == .ready else { return }
        phase = .resetting
    }

    /// Runs the requested reset. Called from the placeholder's task, which is
    /// what guarantees the interface holding the old models is already gone.
    func performReset() async {
        guard phase == .resetting else { return }
        await settle()
        await reset()
        generation += 1
        phase = .ready
    }

    func appDidBecomeActive() {
        mergeCoordinator.appDidBecomeActive()
    }

    private func reset() async {
        let context = container.mainContext
        do {
            try AppReset.eraseStore(in: context)
        } catch {
            errorMessage = "Couldn’t erase everything. Some of your data may still be here; "
                + "try again, or reinstall SoapWiz."
            return
        }
        let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        AppReset.clearDeviceState(rollbackDirectory: documents)
        await NotificationService.cancelAllReminders()
    }

    /// Releasing the views is synchronous, but UIKit lets go of them only when
    /// the runloop turn ends, and only sleeping ends it.
    private func settle() async {
        await Task.yield()
        if settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
        }
    }

    /// Brings a freshly opened store to the state every screen expects.
    private static func prepare(_ context: ModelContext) {
        // Repairs the migration that gave `Ingredient` its identity, before
        // anything installs or merges ingredients.
        IngredientIdentityBackfill.repairSharedIdentitiesLoggingFailure(in: context)
        // Before the seeder, whose fixtures only stock the library's rows.
        IngredientLibraryInstaller.installMissingLoggingFailure(in: context)
        // After the installer, which codes only the rows it adds: this fills the
        // journal code on library rows an earlier build installed without one.
        IngredientCodeBackfill.fillMissingCodesLoggingFailure(in: context)
        DataSeeder.seed(into: context)
        // Before `resolve`, so it only ever has to handle the zero-record case —
        // any duplicate settings rows from a previous sync are already gone.
        DuplicateMerger.mergeAllLoggingFailure(in: context)
        // Repairs the migration that gave `Recipe` its identity, which hands
        // every recipe that predates the field the same one. Independent of the
        // merge above — that one never touches recipes.
        RecipeIdentityBackfill.repairSharedIdentitiesLoggingFailure(in: context)
        // Codes the batches made before batches had one, then settles any code
        // two devices handed out independently. In that order, so a code the
        // backfill has just given is checked like any other.
        BatchCodeBackfill.fillMissingCodesLoggingFailure(in: context)
        BatchCodeDeduplicator.resolveLoggingFailure(in: context)
        _ = AppSettings.resolve(in: context)
    }
}
