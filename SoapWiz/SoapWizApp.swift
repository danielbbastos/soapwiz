//
//  SoapWizApp.swift
//  SoapWiz
//
//  Created by Daniel Bastos on 10/05/2026.
//

import OSLog
import SwiftUI
import SwiftData

@main
struct SoapWizApp: App {
    /// Opens the store as it is created, so everything the launch repairs is
    /// in place before the first view reads it.
    @State private var storeHost: StoreHost

    @Environment(\.scenePhase) private var scenePhase

    @State private var tourLauncher = TourLauncher(isSceneActive: false)

    @State private var proStore = ProStore()

    init() {
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        UITextField.disableNumberPadPopovers()
        UIWindow.dismissKeyboardOnTapOutsideFields()
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
                        .environment(storeHost.inventoryRows)
                        .environment(storeHost.settings)
                        .modelContainer(storeHost.container)
                        // Its own task: the launch decision can wait on iCloud
                        // and shouldn't sit behind the seeding below.
                        .task {
                            #if DEBUG
                            if let phase = TourPhase.launchArgument {
                                tourLauncher.presentForDebug(at: phase)
                                return
                            }
                            #endif
                            await tourLauncher.presentAtLaunchIfDue()
                        }
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
            .environment(tourLauncher)
            .environment(proStore)
            // On the outer view so it lives as long as the app and a store
            // regeneration doesn't restart it.
            .task { await proStore.start() }
            // Outside `ContentView`, so the tour's navigation is its own.
            .fullScreenCover(isPresented: Binding(
                get: { tourLauncher.isPresented && storeHost.phase == .ready },
                set: { if !$0 && tourLauncher.isPresented { tourLauncher.close() } }
            ), onDismiss: {
                tourLauncher.coverDidDismiss()
            }, content: {
                TourCover(
                    currencyCode: storeHost.settings.currencyCode,
                    startingPhase: tourLauncher.presentation?.startingPhase ?? .welcome
                ) { _ in
                    tourLauncher.close()
                }
                // A cover doesn't carry the root's environment into the
                // sandbox's interface, which reads the launcher.
                .environment(tourLauncher)
                .onAppear { tourLauncher.coverDidAppear() }
            })
            // Its own observer with `initial`, so the launcher learns the phase
            // the app started in without the handler below running at launch.
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                tourLauncher.sceneActivityChanged(isActive: newPhase == .active)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Signposts.foreground.emitEvent("Became active")
                }
                // Not while a reset is under way: the placeholder is up and the
                // store is the reset's until it finishes.
                guard newPhase == .active, storeHost.phase == .ready else { return }
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
