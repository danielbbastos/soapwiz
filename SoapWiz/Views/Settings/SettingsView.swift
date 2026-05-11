import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]

    var body: some View {
        NavigationStack {
            List {
                Section("Inventory") {
                    NavigationLink(destination: CategoryListView()) {
                        LabeledContent("Categories", value: "\(categories.count)")
                    }
                    NavigationLink(destination: StorageLocationListView()) {
                        LabeledContent("Storage Locations", value: "\(locations.count)")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
