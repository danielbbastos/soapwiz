import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "flask") {
                IngredientListView()
            }
            Tab("Formulas", systemImage: "flask.roundbottom") {
                FormulaListView()
            }
            Tab("History", systemImage: "clock") {
                NavigationStack {
                    ContentUnavailableView(
                        "Coming Soon",
                        systemImage: "clock",
                        description: Text("Production history will be available in a future update.")
                    )
                    .navigationTitle("History")
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .environment(\.horizontalSizeClass, .compact)
    }
}
