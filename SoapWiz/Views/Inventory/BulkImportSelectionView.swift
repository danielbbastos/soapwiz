import SwiftUI
import SwiftData

/// First step of bulk import: pick which existing ingredients should receive a new
/// purchase. Tapping rows toggles selection; "Next" starts the sequential entry
/// flow with the chosen ingredients in name order.
struct BulkImportSelectionView: View {
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var selection: Set<PersistentIdentifier> = []
    @State private var searchText = ""

    let onCancel: () -> Void
    let onStart: ([Ingredient]) -> Void

    /// Hidden ingredients are left out: recording a purchase against something the
    /// user has said they don't use would contradict the hiding.
    private var visibleIngredients: [Ingredient] {
        ingredients.filter { !$0.isHidden }
    }

    private var selectedIngredients: [Ingredient] {
        visibleIngredients.filter { selection.contains($0.persistentModelID) }
    }

    private var filteredIngredients: [Ingredient] {
        guard !searchText.isEmpty else { return visibleIngredients }
        return visibleIngredients.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleIngredients.isEmpty {
                    HoneyLedgerEmptyState(
                        "No Ingredients",
                        systemImage: "flask",
                        description: "Add ingredients before importing purchases."
                    )
                } else {
                    let filtered = filteredIngredients
                    List {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, ingredient in
                            row(ingredient, position: .position(index: index, count: filtered.count))
                        }
                    }
                    .environment(\.defaultMinListRowHeight, 48)
                    .overlay {
                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .searchHeader("Search ingredients", text: $searchText, showsList: true)
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Bulk Import")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { onStart(selectedIngredients) }
                        .disabled(selection.isEmpty)
                }
            }
        }
    }

    /// A selected row is honey, with its circle filled in `amberText`.
    private func row(_ ingredient: Ingredient, position: LedgerSheetPosition) -> some View {
        let isSelected = selection.contains(ingredient.persistentModelID)
        return Button {
            toggle(ingredient)
        } label: {
            HoneyLedgerPickerRow(name: ingredient.name, state: isSelected ? .selected : .unselected)
        }
        .ledgerListDetailRow(isSelected: isSelected, position: position)
    }

    private func toggle(_ ingredient: Ingredient) {
        let id = ingredient.persistentModelID
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
