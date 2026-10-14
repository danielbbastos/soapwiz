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

    #if DEBUG
    /// Opens the onboarding tour at a given step, for screenshots. Real
    /// first-launch presentation is not wired up yet.
    @State private var showsDebugTour = TourPhase.launchArgument != nil
    private let debugTourPhase = TourPhase.launchArgument ?? .welcome
    #endif

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
            #if DEBUG
            // Outside `ContentView`, so the tour's navigation is its own.
            .fullScreenCover(isPresented: Binding(
                get: { showsDebugTour && storeHost.phase == .ready },
                set: { if !$0 { showsDebugTour = false } }
            )) {
                TourCover(
                    currencyCode: storeHost.settings.currencyCode,
                    startingPhase: debugTourPhase
                ) { _ in
                    showsDebugTour = false
                }
            }
            #endif
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
