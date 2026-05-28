import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]
    @Query private var providers: [Provider]
    @Query private var settingsRecords: [AppSettings]
    private var settings: AppSettings? { settingsRecords.first }

    @State private var showPvpInfo = false

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
                }
                if let settings {
                    Section("Pricing") {
                        HStack {
                            Text("RRP factor")
                            Button {
                                showPvpInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            TextField("4", value: Bindable(settings).$pvpFactor,
                                  format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        }
                    }
                    .sheet(isPresented: $showPvpInfo) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RRP Factor")
                                .font(.headline)
                            Text("A multiplier applied to the total ingredient cost of a product to estimate its recommended retail price (RRP — Recommended Retail Price).\n\nFor example, a factor of 4 means a product costing €2.50 to make would be priced at €10.00.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .presentationDetents([.fraction(0.35)])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
