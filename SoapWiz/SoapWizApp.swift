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
    /// in place before the first view reads it. `nil` only on a fresh install,
    /// where `openStoreAfterEntitlement()` fills it in once StoreKit has
    /// answered or the wait ran out.
    @State private var storeHost: StoreHost?

    @Environment(\.scenePhase) private var scenePhase

    @State private var tourLauncher = TourLauncher(isSceneActive: false)

    @State private var proStore: ProStore

    @State private var upgradePresenter = ProUpgradePresenter()

    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "pro")

    init() {
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        UITextField.disableNumberPadPopovers()
        UIWindow.dismissKeyboardOnTapOutsideFields()
        // Started here, not from a view's task: the listener lives for the app,
        // not for a window or a store regeneration.
        let proStore = ProStore()
        proStore.start()
        _proStore = State(initialValue: proStore)
        let hint = ProEntitlementHint().storedValue
        if StoreSelection.needsEntitlementWait(hint: hint) {
            _storeHost = State(initialValue: nil)
        } else {
            _storeHost = State(initialValue: StoreHost(
                isPro: StoreSelection.launchIsPro(answer: nil, hint: hint)
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let storeHost {
                    content(for: storeHost)
                } else {
                    Color.paper
                        .ignoresSafeArea()
                        .task { await openStoreAfterEntitlement() }
                }
            }
            .alert("Something went wrong", isPresented: resetError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeHost?.errorMessage ?? "")
            }
            .publishesWindowHeight()
            .environment(tourLauncher)
            .environment(proStore)
            // Outside `ContentView`, so the tour's navigation is its own.
            .fullScreenCover(isPresented: Binding(
                get: { tourLauncher.isPresented && storeHost?.phase == .ready },
                set: { if !$0 && tourLauncher.isPresented { tourLauncher.close() } }
            ), onDismiss: {
                tourLauncher.coverDidDismiss()
            }, content: {
                if let storeHost {
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
                }
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
                guard newPhase == .active else { return }
                Task { await proStore.refreshEntitlementHonouringCancellation() }
                guard let storeHost, storeHost.phase == .ready else { return }
                Task {
                    await NotificationService.syncIfEnabled(
                        modelContext: storeHost.container.mainContext
                    )
                }
            }
            // A purchase schedules the reminders at once, and a refund cancels
            // them, without waiting for the next foreground.
            .onChange(of: proStore.isPro) {
                guard let storeHost, storeHost.phase == .ready else { return }
                Task {
                    await NotificationService.syncIfEnabled(
                        modelContext: storeHost.container.mainContext
                    )
                }
            }
            // A reminder setting that arrives from another device or a restore
            // is scheduled at once. Not when the store first appears (`old` is
            // nil): launch syncs by itself. A duplicate run after a toggle is
            // harmless, since syncs are serialized and permission is asked once.
            .onChange(of: storeHost?.settings.reminders) { old, new in
                guard old != nil, new != nil else { return }
                guard let storeHost, storeHost.phase == .ready else { return }
                Task {
                    await NotificationService.syncIfEnabled(
                        modelContext: storeHost.container.mainContext
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func content(for storeHost: StoreHost) -> some View {
        if storeHost.phase == .ready {
            ContentView()
                .id(storeHost.generation)
                .proUpgradeHost()
                .environment(storeHost)
                .environment(storeHost.syncHealth)
                .environment(storeHost.inventoryRows)
                .environment(storeHost.settings)
                .modelContainer(storeHost.container)
                .environment(upgradePresenter)
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
                    // After launch rather than while preparing the store:
                    // whether the device has an iCloud account is only
                    // known asynchronously, and nothing may be seeded
                    // into a store that could sync.
                    await DataSeeder.seedTestDataIfDue(
                        into: storeHost.container.mainContext,
                        activeStore: ModelContainerFactory.activeStore,
                        storeGeneration: storeHost.generation
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

    /// Only a fresh install gets here: with no remembered answer, the store
    /// can't be chosen before StoreKit replies, so the window shows the paper
    /// until it does or the timeout passes.
    private func openStoreAfterEntitlement() async {
        // A re-run placeholder task must never open a second ModelContainer on the same file.
        guard storeHost == nil else { return }
        let clock = ContinuousClock()
        let start = clock.now
        let signpost = Signposts.entitlement.beginInterval("Launch entitlement")
        let answer = await proStore.entitlementAnswer()
        Signposts.entitlement.endInterval("Launch entitlement", signpost)
        let elapsed = (clock.now - start).formatted(.units(allowed: [.milliseconds]))
        let timedOut = answer == nil
        Self.log.notice(
            "Launch entitlement took \(elapsed, privacy: .public), timed out: \(timedOut, privacy: .public)"
        )
        // Checked again: another run may have finished while this one waited.
        guard storeHost == nil else { return }
        // Read now, not before the wait: the purchase listener may have written the hint meanwhile.
        let hint = ProEntitlementHint().storedValue
        storeHost = StoreHost(isPro: StoreSelection.launchIsPro(answer: answer, hint: hint))
    }

    private var resetError: Binding<Bool> {
        Binding(
            get: { storeHost?.errorMessage != nil },
            set: { if !$0 { storeHost?.errorMessage = nil } }
        )
    }
}
