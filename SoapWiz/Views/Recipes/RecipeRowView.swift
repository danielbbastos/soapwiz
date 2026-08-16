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

    /// Built in `init` rather than `body`: the summary walks the recipe's
    /// ingredients, and `body` is re-evaluated far more often than the row is
    /// rebuilt.
    private let summary: RecipeRowSummary

    init(recipe: Recipe, onToggleFavorite: @escaping () -> Void) {
        self.recipe = recipe
        self.onToggleFavorite = onToggleFavorite
        self.summary = RecipeRowSummary(recipe: recipe)
    }

    /// The star sits where the disclosure chevron used to, centred on the row's
    /// full height rather than on the title. It is the row's only accessory now,
    /// so it holds the trailing edge for every layout below.
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if Self.isPhone {
                    phoneLayout
                } else {
                    wideLayout
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FavoriteStarButton(
                isFavorite: recipe.isFavorite,
                action: onToggleFavorite,
                font: .title3
            )
        }
        .padding(.vertical, 6)
    }

    /// Phone: a smaller well, and the description dropped below both columns so
    /// it runs the full width of the row. On a phone the text column beside an
    /// 80pt well is narrow enough that a description truncates after a handful
    /// of words; given the whole width it reads as a sentence.
    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                RecipeRowThumbnail(imageData: recipe.thumbnailData, side: 56)
                VStack(alignment: .leading, spacing: 3) {
                    titleLine
                    subtitleText
                    detailLine(summary.composition, lines: 1)
                    footnoteText
                }
            }
            detailLine(summary.summaryDescription, lines: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// iPad: everything in one column beside the well, which has the width to
    /// carry it without the description wrapping short.
    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeRowThumbnail(imageData: recipe.thumbnailData)
            VStack(alignment: .leading, spacing: 3) {
                titleLine
                subtitleText
                detailLine(summary.composition, lines: 1)
                detailLine(summary.summaryDescription, lines: 2)
                footnoteText
            }
        }
    }

    private var titleLine: some View {
        Text(recipe.name)
            .font(.body.weight(.medium))
            .lineLimit(1)
    }

    private var subtitleText: some View {
        Text(summary.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The composition and description lines, which differ only in how many
    /// lines they may run to. Both sit a step below the subtitle: that buys
    /// roughly a further oil before the tail truncates, and ingredient names
    /// here carry their own "Oil" suffix, so three rarely fit at subheadline
    /// size on a phone. Renders nothing when the recipe has no such line.
    @ViewBuilder
    private func detailLine(_ text: String?, lines: Int) -> some View {
        if let text {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(lines)
                .truncationMode(.tail)
        }
    }

    private var footnoteText: some View {
        Text(summary.footnote)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
