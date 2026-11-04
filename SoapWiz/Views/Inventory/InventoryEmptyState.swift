import SwiftUI

/// What fills the Inventory screen when the list has nothing to draw: no
/// ingredients at all, none in scope yet (the library is installed, the user
/// owns nothing), a search with no hits, or filters that match nothing.
struct InventoryEmptyState: View {
    let model: IngredientListViewModel
    let hasListedIngredients: Bool
    let inScopeTotal: Int

    private var importButton: some View {
        Button("Import from spreadsheet") { model.showingCSVImport = true }
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
            .foregroundStyle(Color.amberText)
    }

    var body: some View {
        if !hasListedIngredients {
            HoneyLedgerEmptyState(
                "No ingredients yet",
                systemImage: "flask",
                description: "Tap + to add one, or bring them in from a spreadsheet."
            ) {
                importButton
            }
        } else if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if inScopeTotal == 0 && !model.hasActiveFilters {
            HoneyLedgerEmptyState(
                "Nothing in your inventory yet",
                systemImage: "flask",
                description: "Search the built-in ingredients, tap + to add your own, or bring them in from a spreadsheet."
            ) {
                importButton
            }
        } else {
            HoneyLedgerEmptyState(
                "No ingredients match",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "Change or clear the filters."
            )
        }
    }
}
