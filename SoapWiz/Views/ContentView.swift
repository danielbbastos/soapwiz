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
        .environment(\.horizontalSizeClass, .compact)
        .environment(navigation)
    }
}
