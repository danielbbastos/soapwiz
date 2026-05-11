import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "flask") {
                IngredientListView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabViewStyle(.tabBarOnly)
    }
}
