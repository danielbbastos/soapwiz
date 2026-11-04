import SwiftUI

/// What the Recipes list shows in place of rows: no recipes at all, a search
/// with no hits, or a collection filter that matches nothing.
struct RecipeListEmptyState: View {
    let hasRecipes: Bool
    let isSearching: Bool
    let searchText: String

    var body: some View {
        if !hasRecipes {
            HoneyLedgerEmptyState(
                "No recipes yet",
                systemImage: "function",
                description: "Tap + to create one."
            )
        } else if isSearching {
            ContentUnavailableView.search(text: searchText)
        } else {
            HoneyLedgerEmptyState(
                "No recipes match",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "No recipes are filed under the selected collections."
            )
        }
    }
}
