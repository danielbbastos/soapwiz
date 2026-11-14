import SwiftUI

/// Home's "You can make" card: the recipes current stock covers, then the ones
/// that are short. Tapping a row opens Create Batch for it.
struct YouCanMakeCard: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(RecipeRows.self) private var recipeRows
    @Environment(InventoryRows.self) private var inventoryRows
    @Environment(BatchRows.self) private var batchRows
    @Environment(SettingsState.self) private var settings
    @Environment(\.homeNow) private var now
    @State private var model = YouCanMakeModel()

    var body: some View {
        let rows = model.rows(
            recipes: recipeRows.recipes,
            ingredients: inventoryRows.ingredients,
            purchases: inventoryRows.purchases,
            batches: batchRows.batches,
            tracksInventory: settings.tracksInventory,
            now: now
        )
        if !rows.isEmpty {
            HomeCard("You can make", tourAnchor: .homeYouCanMake) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        HomeCardDivider()
                    }
                    Button {
                        navigation.createBatch(for: row.recipe)
                    } label: {
                        YouCanMakeRow(row: row)
                    }
                    .buttonStyle(HomeRowButtonStyle(isLast: index == rows.count - 1))
                    .overlay(alignment: .leading) {
                        recipeButton(row.recipe)
                    }
                }
            }
            .id(TourScrollTarget.homeCards)
        }
    }

    /// Over the row's leading edge rather than inside its button, so the two
    /// taps stay separate: the icon opens the recipe, the rest of the row
    /// opens Create Batch.
    private func recipeButton(_ recipe: Recipe) -> some View {
        Button {
            navigation.pushOnHome(recipe)
        } label: {
            Image(systemName: "book.closed")
                .font(.body)
                .foregroundStyle(Color.amberText)
                .frame(width: YouCanMakeRow.iconWidth, height: YouCanMakeRow.iconWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, YouCanMakeRow.iconInset)
        .accessibilityLabel(Text("Open \(recipe.name)"))
    }
}

private struct YouCanMakeRow: View {
    static let iconWidth: CGFloat = 44
    static let iconInset: CGFloat = 8
    private static let textInset = iconInset + iconWidth + 4

    let row: MakeableRecipeRow

    private var accessibilityText: String {
        let trailing = row.isShort ? String(localized: "Short") : row.batchesText
        return [row.recipe.name, row.detail, trailing].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.recipe.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                if let detail = row.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(row.isShort ? Color.danger : Color.inkSoft)
                }
            }
            Spacer(minLength: 8)
            if row.isShort {
                StatusStamp(word: String(localized: "Short"), tone: .danger)
            } else {
                Text.honeyLedgerFigure(row.batchesText)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkFaint)
                .accessibilityHidden(true)
        }
        .padding(.leading, Self.textInset)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
