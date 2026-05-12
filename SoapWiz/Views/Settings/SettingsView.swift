import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]
    @Query private var providers: [Provider]
    @Query private var units: [QuantityUnit]

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
                    NavigationLink(destination: ProviderListView()) {
                        LabeledContent("Providers", value: "\(providers.count)")
                    }
                    NavigationLink(destination: QuantityUnitListView()) {
                        LabeledContent("Quantity Units", value: "\(units.count)")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
