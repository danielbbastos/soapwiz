import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient
    /// The list's model rather than a toggle closure. A closure differs on every
    /// pass of the list, so SwiftUI could never skip a row's body; with only
    /// comparable inputs, a row is redrawn only when its own ingredient changes.
    /// An iCloud import saves many times a second (SW-219).
    let model: IngredientListViewModel

    @Environment(\.editMode) private var editMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Off, the row drops its stamps and the quantity: with no purchases
    /// recorded, all of them would warn about stock never entered.
    private var tracksInventory: Bool {
        model.tracksInventory
    }

    private var stamps: [IngredientStockStamp] {
        IngredientStockStamp.stamps(for: ingredient, tracksInventory: tracksInventory)
    }

    var body: some View {
        let stamps = stamps
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout(stamps: stamps)
            } else {
                standardLayout(stamps: stamps)
            }
        }
        .padding(.vertical, 2)
    }

    private var avatar: some View {
        IngredientAvatar(
            imageData: ingredient.thumbnailData,
            letter: ingredient.avatarLetter,
            color: ingredient.avatarColor
        )
    }

    /// Hidden while selecting, the same way the FAB is: the star would
    /// otherwise consume the tap meant to select the row for a bulk delete.
    @ViewBuilder
    private var favoriteStar: some View {
        if editMode?.wrappedValue != .active {
            FavoriteStarButton(isFavorite: ingredient.isFavorite) {
                model.toggleFavorite(ingredient)
            }
        }
    }

    /// One column at the accessibility sizes: beside the avatar, the quantity
    /// column would squeeze the name until it broke mid-word. The avatar keeps
    /// its size and the row simply grows taller.
    private func accessibilityLayout(stamps: [IngredientStockStamp]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                avatar
                Spacer()
                favoriteStar
            }
            Text(ingredient.name)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            categoryText
            if !stamps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    stampViews(stamps)
                }
            }
            if tracksInventory {
                quantity(stamps: stamps)
            }
        }
    }

    private func standardLayout(stamps: [IngredientStockStamp]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                secondLine(stamps: stamps)
            }
            Spacer()
            if tracksInventory {
                quantity(stamps: stamps)
            }
            // Beside the quantity rather than stacked above it: stacked, the
            // star adds a line to every row and makes the whole list taller.
            // The row's own spacing is all that sets it apart from the quantity:
            // the two carry unrelated things — how much is left, and whether
            // this is a favourite.
            favoriteStar
        }
    }

    /// The category, then the stamps on a line of their own, stacking when they
    /// don't fit side by side. A row without stamps keeps its two lines.
    @ViewBuilder
    private func secondLine(stamps: [IngredientStockStamp]) -> some View {
        categoryText
        if !stamps.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { stampViews(stamps) }
                VStack(alignment: .leading, spacing: 4) { stampViews(stamps) }
            }
        }
    }

    @ViewBuilder
    private var categoryText: some View {
        if let categoryName = ingredient.category?.name {
            Text(categoryName)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
    }

    private func stampViews(_ stamps: [IngredientStockStamp]) -> some View {
        ForEach(stamps, id: \.word) { stamp in
            StatusStamp(word: stamp.word, tone: stamp.tone, glyph: stamp.glyph)
        }
    }

    private func quantity(stamps: [IngredientStockStamp]) -> some View {
        Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
            .font(.body.weight(.medium).monospacedDigit())
            .foregroundStyle(quantityColor(stamps: stamps))
    }

    private func quantityColor(stamps: [IngredientStockStamp]) -> Color {
        if stamps.contains(.out) { return Color.danger }
        if stamps.contains(.low) { return Color.warning }
        if ingredient.purchases.isEmpty { return Color.inkFaint }
        return Color.inkSoft
    }
}
