import SwiftUI
import SwiftData

extension IngredientListView {
    /// Chips are drawn from the in-scope inventory (what the library scope lets
    /// through, ignoring the other filters), not the displayed list: narrowing to
    /// one category must not make every other chip disappear.
    func categoryChips(stock: StockLevels) -> [IngredientCategory] {
        model.visibleCategories(rows.categories, in: rows.ingredients, stock: stock)
    }

    func headerContent(
        showsSearch: Bool,
        categories: [IngredientCategory],
        hasChips: Bool,
        counts: (all: Int, byCategory: [PersistentIdentifier: Int])
    ) -> some View {
        VStack(spacing: 0) {
            // Nothing to search with an empty inventory. The library
            // counts even when none of it is in scope yet.
            if showsSearch {
                SearchField("Search ingredients", text: $model.searchText, tourAnchor: .inventorySearch)
                    .padding(.bottom, 12)
            }
            if hasChips && model.editMode == .inactive {
                InventoryCategoryFilterBar(categories: categories, model: model, counts: counts)
            }
        }
    }
}
