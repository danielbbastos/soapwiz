import SwiftUI
import SwiftData

/// The way back for an ingredient hidden from Inventory.
///
/// Reached from the filter sheet rather than from the list itself: a row standing
/// for something the user chose not to see would defeat the point of hiding it.
struct HiddenIngredientsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]

    let model: IngredientListViewModel

    private var hidden: [Ingredient] { model.hidden(allIngredients) }

    var body: some View {
        let hidden = hidden
        Group {
            if hidden.isEmpty {
                // Reachable by unhiding the last one while standing here, rather
                // than by arriving — the filter sheet only offers the link when
                // there is something to show.
                HoneyLedgerEmptyState(
                    "Nothing Hidden",
                    systemImage: "eye",
                    description: "Ingredients you hide from Inventory show up here."
                )
            } else {
                List {
                    Section {
                        ForEach(Array(hidden.enumerated()), id: \.element.id) { index, ingredient in
                            row(ingredient)
                                .ledgerSheetRow(position: .position(index: index, count: hidden.count))
                        }
                    } header: {
                        // The List's first-header inset leaves the ornament lower than
                        // centred; it clamps this negative padding to about 7pt up.
                        HoneyLedgerOrnament()
                            .padding(.top, -10)
                    }
                }
            }
        }
        .navigationTitle("Hidden Ingredients")
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle("Hidden Ingredients")
        .ledgerBackground()
    }

    /// One column at the accessibility sizes, as in the inventory list: beside
    /// the avatar and the button, the name would break mid-word.
    private func row(_ ingredient: Ingredient) -> some View {
        let avatar = IngredientAvatar(
            imageData: ingredient.thumbnailData,
            letter: ingredient.avatarLetter,
            color: ingredient.avatarColor
        )
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        avatar
                        Spacer()
                        unhideButton(ingredient)
                    }
                    names(ingredient)
                }
            } else {
                HStack(spacing: 12) {
                    avatar
                    names(ingredient)
                    Spacer(minLength: 8)
                    unhideButton(ingredient)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func names(_ ingredient: Ingredient) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .font(.headline)
                .foregroundStyle(Color.ink)
            if let categoryName = ingredient.category?.name {
                Text(categoryName)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }

    /// `.borderless` so the tap lands on the button rather than on the row,
    /// the same way the favourite star does in the inventory list.
    private func unhideButton(_ ingredient: Ingredient) -> some View {
        Button("Unhide") { model.unhide(ingredient) }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.amberText)
    }
}
