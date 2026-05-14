import SwiftUI
import SwiftData

struct InventoryFilterView: View {
    @Bindable var model: IngredientListViewModel

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query(sort: \QuantityUnit.name) private var units: [QuantityUnit]

    @Environment(\.dismiss) private var dismiss

    private var categoryLabel: String {
        switch model.selectedCategories.count {
        case 0: return "All"
        case 1:
            return categories.first { model.selectedCategories.contains($0.persistentModelID) }?.name ?? "1 selected"
        default:
            return "\(model.selectedCategories.count) selected"
        }
    }

    private var unitLabel: String {
        switch model.selectedUnits.count {
        case 0: return "All"
        case 1:
            return units.first { model.selectedUnits.contains($0.persistentModelID) }
                .map { "\($0.name) (\($0.symbol))" } ?? "1 selected"
        default:
            return "\(model.selectedUnits.count) selected"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !categories.isEmpty {
                    LabeledContent("Category") {
                        Menu(categoryLabel) {
                            ForEach(categories) { category in
                                let id = category.persistentModelID
                                Button {
                                    if model.selectedCategories.contains(id) {
                                        model.selectedCategories.remove(id)
                                    } else {
                                        model.selectedCategories.insert(id)
                                    }
                                } label: {
                                    if model.selectedCategories.contains(id) {
                                        Label(category.name, systemImage: "checkmark")
                                    } else {
                                        Text(category.name)
                                    }
                                }
                            }
                        }
                    }
                }

                Picker("Stock Status", selection: $model.stockStatus) {
                    ForEach(StockStatusFilter.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.menu)

                if !units.isEmpty {
                    LabeledContent("Unit Type") {
                        Menu(unitLabel) {
                            ForEach(units) { unit in
                                let id = unit.persistentModelID
                                Button {
                                    if model.selectedUnits.contains(id) {
                                        model.selectedUnits.remove(id)
                                    } else {
                                        model.selectedUnits.insert(id)
                                    }
                                } label: {
                                    if model.selectedUnits.contains(id) {
                                        Label("\(unit.name) (\(unit.symbol))", systemImage: "checkmark")
                                    } else {
                                        Text("\(unit.name) (\(unit.symbol))")
                                    }
                                }
                            }
                        }
                    }
                }

                Picker("Expiry Date", selection: $model.expiryFilter) {
                    ForEach(ExpiryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.hasActiveFilters {
                        Button("Clear All") { model.clearFilters() }
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
