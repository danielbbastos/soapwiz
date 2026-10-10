import SwiftUI
import UIKit

struct RecipeRowView: View {
    /// Deliberately the device idiom rather than `horizontalSizeClass`.
    /// `ContentView` pins the whole `TabView` to `.compact` so the tab bar stays
    /// bottom-mounted on iPad, which leaves the size class saying "compact"
    /// everywhere and useless as a phone/iPad signal. Evaluated once: the idiom
    /// cannot change while the app runs.
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    let recipe: Recipe
    let onToggleFavorite: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Built in `init` rather than `body`: the summary walks the recipe's
    /// ingredients, and `body` is re-evaluated far more often than the row is
    /// rebuilt.
    private let summary: RecipeRowSummary

    init(recipe: Recipe, onToggleFavorite: @escaping () -> Void) {
        self.recipe = recipe
        self.onToggleFavorite = onToggleFavorite
        self.summary = RecipeRowSummary(recipe: recipe)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.vertical, 6)
    }

    /// A recipe has no colour of its own, so the well's is derived from its
    /// name: the same recipe keeps the same colour, and no field is added to
    /// sync. Smaller on a phone, where the text beside it has less width to
    /// spare.
    private var thumbnail: some View {
        RecipeRowThumbnail(
            imageData: recipe.thumbnailData,
            color: AvatarColor.resolve("", fallbackSeed: recipe.name),
            side: Self.isPhone ? 56 : 80
        )
    }

    private var favoriteStar: some View {
        FavoriteStarButton(isFavorite: recipe.isFavorite, action: onToggleFavorite)
    }

    /// The star is centred on the row's full height rather than on the title.
    private var standardLayout: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                textColumn(lineLimit: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            favoriteStar
        }
    }

    /// One column at the accessibility sizes: beside the well, the text column
    /// would be squeezed to a word or two a line. The well keeps its size and
    /// the row simply grows taller.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                thumbnail
                Spacer()
                favoriteStar
            }
            textColumn(lineLimit: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textColumn(lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .lineLimit(lineLimit)
            Text(summary.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
                .lineLimit(lineLimit)
            if let composition = summary.composition {
                Text(composition)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(lineLimit)
            }
            Text(summary.footnote)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.inkFaint)
                .padding(.top, 2)
        }
    }
}
