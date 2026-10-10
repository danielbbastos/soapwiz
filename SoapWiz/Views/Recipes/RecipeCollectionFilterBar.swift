import SwiftUI
import SwiftData

/// Horizontal, multi-select chips that narrow the recipe list to one or more
/// collections. A leading "All" chip clears the selection, since nothing
/// selected already means the whole list.
struct RecipeCollectionFilterBar: View {
    let collections: [RecipeCollection]
    @Bindable var model: RecipeListViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip("All", isSelected: !model.hasActiveFilters) {
                    model.clearFilters()
                }
                ForEach(collections) { collection in
                    FilterChip(
                        collection.name,
                        isSelected: model.selectedCollections.contains(collection.persistentModelID),
                        dot: collection.color.pigment
                    ) {
                        model.toggle(collection)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // Less the chips' own padding, so the first chip lines up with the
        // capped list below it.
        .readableWidth(inset: 16)
    }
}
