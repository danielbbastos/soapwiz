import SwiftUI
import SwiftData

/// Horizontal, multi-select chips that narrow the recipe list to one or more
/// collections. Nothing selected means the whole list, so the bar starts out
/// inert and only ever subtracts.
struct RecipeCollectionFilterBar: View {
    let collections: [RecipeCollection]
    @Bindable var model: RecipeListViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.hasActiveFilters {
                    clearChip
                }
                ForEach(collections) { collection in
                    FilterChip(
                        collection.name,
                        isSelected: model.selectedCollections.contains(collection.persistentModelID),
                        tint: collection.color.tint
                    ) {
                        model.toggle(collection)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var clearChip: some View {
        Button {
            model.clearFilters()
        } label: {
            Label("Clear", systemImage: "xmark")
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.secondary)
                .background(Color.cardBackground, in: .capsule)
                .overlay(Capsule().strokeBorder(.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}
