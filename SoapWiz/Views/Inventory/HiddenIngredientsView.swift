import SwiftUI
import SwiftData

/// The way back for an ingredient hidden from Inventory.
///
/// Reached from the filter sheet rather than from the list itself: a row standing
/// for something the user chose not to see would defeat the point of hiding it.
struct HiddenIngredientsView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]

    let model: IngredientListViewModel

    private var hidden: [Ingredient] { model.hidden(allIngredients) }

    var body: some View {
        Group {
            if hidden.isEmpty {
                // Reachable by unhiding the last one while standing here, rather
                // than by arriving — the filter sheet only offers the link when
                // there is something to show.
                ContentUnavailableView(
                    "Nothing Hidden",
                    systemImage: "eye",
                    description: Text("Ingredients you hide from Inventory show up here.")
                )
            } else {
                List {
                    ForEach(hidden) { ingredient in
                        row(ingredient)
                            .listRowBackground(Color.cardBackground)
                    }
                }
            }
        }
        .navigationTitle("Hidden Ingredients")
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle("Hidden Ingredients")
        .warmBackground()
    }

    private func row(_ ingredient: Ingredient) -> some View {
        HStack {
            IngredientAvatar(
                imageData: ingredient.thumbnailData,
                letter: ingredient.avatarLetter,
                color: ingredient.avatarColor
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.body.weight(.medium))
                if let categoryName = ingredient.category?.name {
                    Text(categoryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // `.borderless` so the tap lands on the button rather than on the row,
            // the same way the favourite star does in the inventory list.
            Button("Unhide") { model.unhide(ingredient) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
