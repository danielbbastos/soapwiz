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
        _ = AppSettings.resolve(in: container.mainContext)
        sharedModelContainer = container
        _syncHealth = State(
            initialValue: SyncHealthMonitor(activeStore: ModelContainerFactory.activeStore)
        )
    }

    @State private var mergeCoordinator: DuplicateMergeCoordinator?

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncHealth)
                .task {
                    // Held for the app's lifetime so its remote-change observer
                    // stays registered; CloudKit imports duplicates long after launch.
                    if mergeCoordinator == nil {
                        mergeCoordinator = DuplicateMergeCoordinator(
                            context: sharedModelContainer.mainContext
                        )
                    }
                    await NotificationService.syncIfEnabled(
                        modelContext: sharedModelContainer.mainContext
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    mergeCoordinator?.mergeNow()
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
