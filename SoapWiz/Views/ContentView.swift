import SwiftUI

struct ContentView: View {
    @State private var navigation = AppNavigation()

    var body: some View {
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
        // The asset-catalog global accent isn't picked up at runtime on
        // iPadOS 26 (`Color.accentColor`, the tab bar, and sidebar selection
        // all resolve to default blue), so load the colorset by name and
        // propagate it explicitly from the root.
        .tint(Color("AccentColor"))
        .environment(navigation)
    }
}
