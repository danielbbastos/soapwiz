import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "flask") {
                IngredientListView()
            }
            Tab("Recipes", systemImage: "function") {
                RecipeListView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                BatchListView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .environment(\.horizontalSizeClass, .compact)
    }
}
