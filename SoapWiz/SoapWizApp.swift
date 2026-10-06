//
//  SoapWizApp.swift
//  SoapWiz
//
//  Created by Daniel Bastos on 10/05/2026.
//

import SwiftUI
import SwiftData

@main
struct SoapWizApp: App {
    let sharedModelContainer: ModelContainer

    /// Built here rather than from a property default so it is unambiguously
    /// created *after* `makeProduction()` has recorded which store it opened.
    @State private var syncHealth: SyncHealthMonitor

    init() {
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        let container = ModelContainerFactory.makeProduction()
        // Straight after the store opens, so its import observer is registered
        // before the launch merge below: an import that finished in between
        // would otherwise go unmerged until the next one. Built here rather than
        // in a task so it also exists before the scene's first activation, which
        // it has to see in order to skip it. Held for the app's lifetime;
        // CloudKit imports duplicates long after launch.
        _mergeCoordinator = State(
            initialValue: DuplicateMergeCoordinator(context: container.mainContext)
        )
        // Repairs the migration that gave `Ingredient` its identity, before
        // anything installs or merges ingredients.
        IngredientIdentityBackfill.repairSharedIdentitiesLoggingFailure(in: container.mainContext)
        // Before the seeder, whose fixtures only stock the library's rows.
        IngredientLibraryInstaller.installMissingLoggingFailure(in: container.mainContext)
        // After the installer, which codes only the rows it adds: this fills the
        // journal code on library rows an earlier build installed without one.
        IngredientCodeBackfill.fillMissingCodesLoggingFailure(in: container.mainContext)
        DataSeeder.seed(into: container.mainContext)
        // Before `resolve`, so it only ever has to handle the zero-record case —
        // any duplicate settings rows from a previous sync are already gone.
        DuplicateMerger.mergeAllLoggingFailure(in: container.mainContext)
        // Repairs the migration that gave `Recipe` its identity, which hands
        // every recipe that predates the field the same one. Independent of the
        // merge above — that one never touches recipes.
        RecipeIdentityBackfill.repairSharedIdentitiesLoggingFailure(in: container.mainContext)
        // Codes the batches made before batches had one, then settles any code
        // two devices handed out independently. In that order, so a code the
        // backfill has just given is checked like any other.
        BatchCodeBackfill.fillMissingCodesLoggingFailure(in: container.mainContext)
        BatchCodeDeduplicator.resolveLoggingFailure(in: container.mainContext)
        _ = AppSettings.resolve(in: container.mainContext)
        sharedModelContainer = container
        _syncHealth = State(
            initialValue: SyncHealthMonitor(activeStore: ModelContainerFactory.activeStore)
        )
    }

    @State private var mergeCoordinator: DuplicateMergeCoordinator

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncHealth)
                .task {
                    // After launch rather than with the rest of the seeding:
                    // whether the store syncs to an account is only known
                    // asynchronously.
                    await DataSeeder.seedTestBatchesIfDue(
                        into: sharedModelContainer.mainContext,
                        activeStore: ModelContainerFactory.activeStore
                    )
                    await NotificationService.syncIfEnabled(
                        modelContext: sharedModelContainer.mainContext
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    mergeCoordinator.appDidBecomeActive()
                    Task {
                        await NotificationService.syncIfEnabled(
                            modelContext: sharedModelContainer.mainContext
                        )
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
