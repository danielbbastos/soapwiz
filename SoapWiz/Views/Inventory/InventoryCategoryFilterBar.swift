import SwiftUI
import SwiftData

/// Horizontal, multi-select category chips above the inventory list — the fast
/// path for the filter the sheet makes expensive. A leading "All" chip clears
/// the category filter, since an empty selection already means every category.
///
/// The chips drive `IngredientListViewModel.selectedCategories`, the same state
/// the filter sheet edits, so the two can never disagree.
struct InventoryCategoryFilterBar: View {
    let categories: [IngredientCategory]
    @Bindable var model: IngredientListViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip("All", isSelected: model.isShowingAllCategories) {
                    model.selectAllCategories()
                }
                ForEach(categories) { category in
                    FilterChip(
                        category.name,
                        isSelected: model.selectedCategories.contains(category.persistentModelID)
                    ) {
                        model.toggleCategory(category)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }
}
