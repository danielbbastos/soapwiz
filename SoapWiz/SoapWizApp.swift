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
        let schema = Schema([
            Ingredient.self,
            IngredientPurchase.self,
            IngredientCategory.self,
            StorageLocation.self,
            Provider.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeProduct.self,
            Batch.self,
            BatchLineItem.self,
            AppSettings.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed — wipe store and retry (dev only, no production data at risk)
            let storeURL = modelConfiguration.url
            let shmURL = storeURL.appendingPathExtension("shm")
            let walURL = storeURL.appendingPathExtension("wal")
            for url in [storeURL, shmURL, walURL] {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }

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
