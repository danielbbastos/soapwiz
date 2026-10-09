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

    /// The rows offered from `category`, favourites first and each group by name.
    static func candidates(from ingredients: [Ingredient], category: String, selected: Ingredient?) -> [Ingredient] {
        ingredients
            .filter { $0.category?.name == category }
            .filter { !$0.isHidden || $0.persistentModelID == selected?.persistentModelID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .favoritesFirst
    }

    private var candidates: [Ingredient] {
        Self.candidates(from: ingredients, category: config.category, selected: selected)
    }

    private var filtered: [Ingredient] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if candidates.isEmpty {
                HoneyLedgerEmptyState(
                    LocalizedStringKey(config.emptyTitle),
                    systemImage: "tray",
                    description: LocalizedStringKey(config.emptyDescription)
                )
            } else {
                let rows = filtered
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, ingredient in
                        let isSelected = selected?.persistentModelID == ingredient.persistentModelID
                        Button {
                            selected = ingredient
                            dismiss()
                        } label: {
                            HoneyLedgerPickerRow(name: ingredient.name, state: isSelected ? .selected : .unselected)
                        }
                        .ledgerListDetailRow(
                            isSelected: isSelected,
                            position: .position(index: index, count: rows.count)
                        )
                    }
                }
                .environment(\.defaultMinListRowHeight, 48)
                .overlay {
                    if rows.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .searchHeader("Search", text: $searchText, showsList: true)
            }
        }
        .readableWidth()
        .navigationTitle(config.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle(config.navigationTitle)
        .ledgerBackground()
    }
}
