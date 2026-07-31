import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var navigation = AppNavigation()
    @State private var restore = RestoreCoordinator()

    private var importConfirmation: Binding<Bool> {
        Binding(
            get: { restore.pendingImport != nil },
            set: { if !$0 { restore.cancel() } }
        )
    }

    private var restoreError: Binding<Bool> {
        Binding(
            get: { restore.errorMessage != nil },
            set: { if !$0 { restore.errorMessage = nil } }
        )
    }

    private var rollbackNotice: Binding<Bool> {
        Binding(
            get: { restore.rollbackFile != nil },
            set: { if !$0 { restore.rollbackFile = nil } }
        )
    }

    var body: some View {
        Group {
            if restore.phase == .restoring {
                RestoreProgressView()
                    .task { await restore.perform(in: modelContext) }
            } else {
                // The `if` is what gives the rebuilt tabs a fresh identity; `.id` is
                // insurance, so the history tab gets a brand-new `NavigationStack`
                // rather than one diffed against a path that outlived the wipe.
                tabs.id(restore.generation)
            }
        }
        .environment(navigation)
        .environment(restore)
        .alert("Replace all data?", isPresented: importConfirmation) {
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
        .alert("Something went wrong", isPresented: restoreError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restore.errorMessage ?? "")
        }
        .alert("Import complete", isPresented: rollbackNotice) {
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
        TabView(selection: $navigation.selectedTab) {
            Tab("Inventory", systemImage: "flask", value: AppTab.inventory) {
                IngredientListView()
            }
            Tab("Recipes", systemImage: "function", value: AppTab.recipes) {
                RecipeListView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                BatchListView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .fontDesign(.rounded)
        .environment(\.horizontalSizeClass, .compact)
    }
}
