import SwiftUI
import SwiftData

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

    /// The category to offer, e.g. `IngredientCategory.Name.lyes`.
    let category: String
    let navigationTitle: String
    let emptyTitle: String
    let emptyDescription: String

    @Environment(\.dismiss) private var dismiss
    @Query private var ingredients: [Ingredient]
    @State private var searchText: String = ""

    private var candidates: [Ingredient] {
        ingredients
            .filter { $0.category?.name == category }
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
                    emptyTitle,
                    systemImage: "tray",
                    description: Text(emptyDescription)
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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle(navigationTitle)
        .warmBackground()
    }
}
