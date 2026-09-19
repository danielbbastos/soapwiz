import SwiftUI
import SwiftData

/// What one `CategoryIngredientPickerView` offers: the category to filter to and
/// the copy for its title and empty state. The two recipe pickers are constants
/// so the strings live in one place.
struct CategoryIngredientPickerConfig {
    let category: String
    let navigationTitle: String
    let emptyTitle: String
    let emptyDescription: String

    static let lye = CategoryIngredientPickerConfig(
        category: IngredientCategory.Name.lyes,
        navigationTitle: "Lye ingredient",
        emptyTitle: "No lye ingredients",
        emptyDescription: "Add an ingredient to the \"Lyes\" category."
    )

    static let neutralizer = CategoryIngredientPickerConfig(
        category: IngredientCategory.Name.additives,
        navigationTitle: "Neutraliser ingredient",
        emptyTitle: "No additives",
        emptyDescription: "Add an ingredient to the \"Additives\" category."
    )
}

/// Picks a single ingredient from one category — the lye a recipe saponifies
/// with, or the additive its Failor neutraliser is dosed from. Hidden rows drop
/// out of the choices, with one exception: whichever row this recipe already uses
/// stays listed even when hidden, so a recipe whose ingredient was hidden doesn't
/// open looking unset when it isn't.
///
/// Distinct from `IngredientPickerView`, which is the multi-select adder for a
/// recipe's oil, additive and fragrance rows.
struct CategoryIngredientPickerView: View {
    @Binding var selected: Ingredient?
    let config: CategoryIngredientPickerConfig

    @Environment(\.dismiss) private var dismiss
    @Query private var ingredients: [Ingredient]
    @State private var searchText: String = ""

    private var candidates: [Ingredient] {
        ingredients
            .filter { $0.category?.name == config.category }
            .filter { !$0.isHidden || $0.persistentModelID == selected?.persistentModelID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filtered: [Ingredient] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                ContentUnavailableView(
                    config.emptyTitle,
                    systemImage: "tray",
                    description: Text(config.emptyDescription)
                )
            } else {
                ForEach(filtered) { ingredient in
                    let isSelected = selected?.persistentModelID == ingredient.persistentModelID
                    Button {
                        selected = ingredient
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(ingredient.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .listRowBackground(isSelected ? Color.selectedRowBackground : Color.cardBackground)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle(config.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle(config.navigationTitle)
        .warmBackground()
    }
}
