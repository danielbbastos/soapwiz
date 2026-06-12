import SwiftUI
import SwiftData

struct InventoryFilterView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Bindable var model: IngredientListViewModel

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
            return model.selectedUnits.first.map { "\($0.label) (\($0.rawValue))" } ?? "1 selected"
        default:
            return "\(model.selectedUnits.count) selected"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !categories.isEmpty {
                    LabeledContent("Category") {
                        categoryMenu
                    }
                    .listRowBackground(Color.cardBackground)
                }

                Picker("Stock Status", selection: $model.stockStatus) {
                    ForEach(StockStatusFilter.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .listRowBackground(Color.cardBackground)

                LabeledContent("Unit Type") {
                    unitMenu
                }
                .listRowBackground(Color.cardBackground)

                Picker("Expiry Date", selection: $model.expiryFilter) {
                    ForEach(ExpiryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Filters")
            .warmBackground()
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

    private var categoryMenu: some View {
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

    private var unitMenu: some View {
        Menu(unitLabel) {
            ForEach(IngredientUnit.allCases, id: \.self) { unit in
                Button {
                    if model.selectedUnits.contains(unit) {
                        model.selectedUnits.remove(unit)
                    } else {
                        model.selectedUnits.insert(unit)
                    }
                } label: {
                    if model.selectedUnits.contains(unit) {
                        Label("\(unit.label) (\(unit.rawValue))", systemImage: "checkmark")
                    } else {
                        Text("\(unit.label) (\(unit.rawValue))")
                    }
                }
            }
        }
    }
}
