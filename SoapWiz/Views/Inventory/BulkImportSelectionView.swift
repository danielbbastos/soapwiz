import SwiftUI
import SwiftData

/// First step of bulk import: pick which existing ingredients should receive a new
/// purchase. Tapping rows toggles selection; "Next" starts the sequential entry
/// flow with the chosen ingredients in name order.
struct BulkImportSelectionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// A picker row: the state at the leading edge, and a selected row in honey
    /// with its circle filled in `amberText`. At accessibility text sizes the
    /// name moves under the circle instead of breaking mid-word beside it.
    private func row(_ ingredient: Ingredient, position: LedgerSheetPosition) -> some View {
        let isSelected = selection.contains(ingredient.persistentModelID)
        let circle = Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.amberText : Color.inkSoft)
            .accessibilityHidden(true)
        let name = Text(ingredient.name)
            .foregroundStyle(Color.ink)
        return Button {
            toggle(ingredient)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        circle
                        name
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        circle
                        name
                        Spacer()
                    }
                }
            }
            .contentShape(.rect)
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
