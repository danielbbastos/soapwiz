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
    /// Opens the store as it is created, so everything the launch repairs is
    /// in place before the first view reads it.
    @State private var storeHost: StoreHost

    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        _storeHost = State(initialValue: StoreHost())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if storeHost.phase == .ready {
                    ContentView()
                        .id(storeHost.generation)
                        .environment(storeHost)
                        .environment(storeHost.syncHealth)
                        .modelContainer(storeHost.container)
                        .task {
                            // After launch rather than with the rest of the
                            // seeding: whether the store syncs to an account
                            // is only known asynchronously.
                            await DataSeeder.seedTestBatchesIfDue(
                                into: storeHost.container.mainContext,
                                activeStore: ModelContainerFactory.activeStore
                            )
                            await NotificationService.syncIfEnabled(
                                modelContext: storeHost.container.mainContext
                            )
                        }
                } else {
                    RestoreProgressView(title: "Erasing everything…")
                        .task { await storeHost.performReset() }
                }
            }
            .alert("Something went wrong", isPresented: resetError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeHost.errorMessage ?? "")
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Not while a reset is under way: the placeholder is up and the
                // store is the reset's until it finishes.
                guard newPhase == .active, storeHost.phase == .ready else { return }
                storeHost.appDidBecomeActive()
                Task {
                    await NotificationService.syncIfEnabled(
                        modelContext: storeHost.container.mainContext
                    )
                }
            }
        }
    }

    private var resetError: Binding<Bool> {
        Binding(
            get: { storeHost.errorMessage != nil },
            set: { if !$0 { storeHost.errorMessage = nil } }
        )
    }
}
