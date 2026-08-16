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
        DataSeeder.seed(into: container.mainContext)
        // Before `resolve`, so it only ever has to handle the zero-record case —
        // any duplicate settings rows from a previous sync are already gone.
        DuplicateMerger.mergeAllLoggingFailure(in: container.mainContext)
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
