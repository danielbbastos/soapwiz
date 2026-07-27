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
    init() {
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
    }

    var sharedModelContainer: ModelContainer = {
        let container = ModelContainerFactory.makeProduction()
        DataSeeder.seed(into: container.mainContext)
        _ = AppSettings.resolve(in: container.mainContext)
        return container
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationService.syncIfEnabled(
                        modelContext: sharedModelContainer.mainContext
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
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
