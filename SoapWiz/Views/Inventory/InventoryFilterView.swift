import SwiftUI
import SwiftData

struct InventoryFilterView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Bindable var model: IngredientListViewModel

    private var hiddenIngredients: [Ingredient] { model.hidden(allIngredients) }

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
                    categoryMenu
                        .listRowBackground(Color.cardBackground)
                }

                if model.tracksInventory {
                    stockStatusMenu
                        .listRowBackground(Color.cardBackground)
                }

                unitMenu
                    .listRowBackground(Color.cardBackground)

                if model.tracksInventory {
                    expiryMenu
                        .listRowBackground(Color.cardBackground)
                }

                // Deliberately not a filter, and so deliberately absent from
                // `activeFilterCount`: hiding is a lasting decision about an
                // ingredient, not a temporary narrowing of the list.
                if !hiddenIngredients.isEmpty {
                    Section {
                        NavigationLink {
                            HiddenIngredientsView(model: model)
                        } label: {
                            LabeledContent("Hidden Ingredients", value: "\(hiddenIngredients.count)")
                        }
                    } footer: {
                        Text("Hidden ingredients stay out of Inventory and out of recipe ingredient pickers. Unhide one to use it again.")
                    }
                    .listRowBackground(Color.cardBackground)
                }
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

    /// Multi-select, so the menu is pinned open: otherwise every tap dismissed
    /// it and picking three categories meant opening it three times. Unlike
    /// `.contextMenu`, whose content SwiftUI snapshots once, a `Menu`
    /// re-evaluates — so the checkmarks still follow each tap. See the note in
    /// `RecipeCollectionsPickerSheet`, which rejected this API for that reason.
    private var categoryMenu: some View {
        filterMenu(title: "Category", value: categoryLabel) {
            ForEach(categories) { category in
                Button {
                    model.toggleCategory(category)
                } label: {
                    MenuSelectionLabel(
                        category.name,
                        isSelected: model.selectedCategories.contains(category.persistentModelID)
                    )
                }
            }
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var unitMenu: some View {
        filterMenu(title: "Unit Type", value: unitLabel) {
            ForEach(IngredientUnit.allCases, id: \.self) { unit in
                Button {
                    if model.selectedUnits.contains(unit) {
                        model.selectedUnits.remove(unit)
                    } else {
                        model.selectedUnits.insert(unit)
                    }
                } label: {
                    MenuSelectionLabel(
                        "\(unit.label) (\(unit.rawValue))",
                        isSelected: model.selectedUnits.contains(unit)
                    )
                }
            }
        }
        .menuActionDismissBehavior(.disabled)
    }

    /// Single-select, so the default dismiss-on-tap is right: the menu has done
    /// its job the moment one option is picked.
    private var stockStatusMenu: some View {
        filterMenu(title: "Stock Status", value: model.stockStatus.rawValue) {
            ForEach(StockStatusFilter.allCases) { status in
                Button {
                    model.stockStatus = status
                } label: {
                    MenuSelectionLabel(status.rawValue, isSelected: model.stockStatus == status)
                }
            }
        }
    }

    private var expiryMenu: some View {
        filterMenu(title: "Expiry Date", value: model.expiryFilter.rawValue) {
            ForEach(ExpiryFilter.allCases) { filter in
                Button {
                    model.expiryFilter = filter
                } label: {
                    MenuSelectionLabel(filter.rawValue, isSelected: model.expiryFilter == filter)
                }
            }
        }
    }

    /// One filter row: a menu whose label fills the row, so a tap anywhere on it
    /// opens the menu. `PickerMenuRowLabel` spans the row but its `Spacer` is not
    /// hit-tested on its own — without `contentShape` only the value text on the
    /// right responded.
    private func filterMenu<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            PickerMenuRowLabel(title: title, value: value)
                .contentShape(.rect)
        }
        .tint(.primary)
    }
}
