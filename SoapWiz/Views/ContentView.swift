import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsState.self) private var settings
    @Environment(\.isTourSandbox) private var isTourSandbox
    @Environment(TourLauncher.self) private var tourLauncher

    /// Absent in the tour's sandbox, which has no upgrade sheet.
    @Environment(ProUpgradePresenter.self) private var upgradePresenter: ProUpgradePresenter?

    @FreeTierGateEnvironment private var freeTier

    @State private var navigation: AppNavigation
    @State private var restore = RestoreCoordinator()

    /// The navigation is handed in so the onboarding tour can drive the tabs
    /// from outside; the app itself lets each launch make its own.
    init(navigation: AppNavigation? = nil) {
        _navigation = State(initialValue: navigation ?? AppNavigation())
    }

    /// Presents an alert for as long as the coordinator holds a value at `keyPath`,
    /// and clears it again on dismissal. Every alert here is driven by a value that
    /// is either there or not.
    private func presenting<T>(
        _ keyPath: ReferenceWritableKeyPath<RestoreCoordinator, T?>
    ) -> Binding<Bool> {
        Binding(
            get: { restore[keyPath: keyPath] != nil },
            set: { if !$0 { restore[keyPath: keyPath] = nil } }
        )
    }

    var body: some View {
        Group {
            if restore.phase == .restoring {
                RestoreProgressView()
                    .task {
                        await restore.perform(
                            in: modelContext,
                            isPro: freeTier.gate.isUnlimited
                        )
                    }
            } else {
                // The `if` is what gives the rebuilt tabs a fresh identity; `.id` is
                // insurance, so the history tab gets a brand-new `NavigationStack`
                // rather than one diffed against a path that outlived the wipe.
                tabs.id(restore.generation)
            }
        }
        .environment(navigation)
        .environment(restore)
        .environment(\.currencyCode, settings.currencyCode)
        // A recipe file tapped in Mail, Messages or Files arrives here. Routed
        // to the Recipes tab, which opens the import review for it. Only file
        // URLs are ours to open; the guard drops anything else the scene is
        // handed.
        .onOpenURL { url in
            guard url.isFileURL, !isTourSandbox else { return }
            tourLauncher.noteExternalOpen()
            navigation.openRecipeFile(url)
        }
        .onChange(of: upgradePresenter?.settingsRequest) { _, request in
            guard request != nil, !isTourSandbox else { return }
            navigation.selectedTab = .settings
        }
        // The tour ran over a sandbox, so the real app is still wherever the
        // user left it; Inventory is where the first-launch story ends. A
        // replay or debug showing leaves the app where it was.
        .onChange(of: tourLauncher.launchTourEnded) {
            guard !isTourSandbox else { return }
            navigation.selectedTab = .inventory
        }
        .alert("Replace all data?", isPresented: presenting(\.pendingImport)) {
            Button("Replace", role: .destructive) {
                // Without this the teardown animates, which keeps the outgoing
                // screens mounted — and re-evaluating — while the store is wiped.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    restore.begin(navigation: navigation)
                }
            }
            Button("Cancel", role: .cancel) {
                restore.cancel()
            }
        } message: {
            Text("This permanently deletes everything currently in SoapWiz and replaces it "
                 + "with the contents of this backup. This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: presenting(\.errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restore.errorMessage ?? "")
        }
        .alert("Import complete", isPresented: presenting(\.rollbackFile)) {
            Button("Save Previous Data") {
                if let file = restore.rollbackFile {
                    restore.rollbackFile = nil
                    restore.rollbackShare = file
                }
            }
            Button("Done", role: .cancel) {
                restore.rollbackFile = nil
            }
        } message: {
            Text("Your previous data was saved to a rollback file before it was replaced. "
                 + "Save it somewhere safe if you might need to go back.")
        }
        .sheet(item: $restore.rollbackShare) { file in
            ShareSheet(items: [file.url])
        }
    }

    /// The interface proper. Held apart from `body` because a restore takes it down
    /// and rebuilds it, and the alerts above have to outlive that.
    private var tabs: some View {
        let _: Void = HoneyLedgerTabBarAppearance.applied
        return TabView(selection: $navigation.selectedTab) {
            Tab(value: AppTab.inventory) {
                IngredientListView().tint(nil)
            } label: {
                tabLabel("Inventory", systemImage: "flask")
            }
            Tab(value: AppTab.recipes) {
                RecipeListView().tint(nil)
            } label: {
                tabLabel("Recipes", systemImage: "function")
            }
            Tab(value: AppTab.history) {
                BatchListView().tint(nil)
            } label: {
                tabLabel("History", systemImage: "clock.arrow.circlepath")
            }
            Tab(value: AppTab.settings) {
                SettingsView().tint(nil)
            } label: {
                tabLabel("Settings", systemImage: "gearshape")
            }
        }
        .tabViewStyle(.tabBarOnly)
        // The selected tab in `amberText`. Each tab's content drops the tint
        // again, so its buttons keep their own colours.
        .tint(Color.amberText)
        // Inside the font and size-class settings below, so the form keeps the
        // look it had as a push.
        .fullScreenCover(item: $navigation.recipeFormRequest, onDismiss: navigation.recipeFormDidClose) { request in
            RecipeFormCover(request: request)
        }
        // Up here for the same reason as the cover: a sheet the detail screen
        // presented closed when a width change moved the detail to the other
        // stack (SW-218).
        .sheet(item: $navigation.detailSheetRequest, onDismiss: navigation.detailSheetDidClose) { request in
            DetailSheetHost(request: request)
        }
        .fontDesign(.rounded)
        .environment(\.horizontalSizeClass, .compact)
        // Outside the TabView so the tab bar is dimmed too, and after the
        // size class above so the caption card sees the real one.
        .tourOverlayHost(.tabs)
    }

    /// An outline glyph in either state: the system fills the selected one.
    private func tabLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .environment(\.symbolVariants, .none)
    }
}
