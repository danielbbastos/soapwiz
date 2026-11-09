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
            HomeCard("You can make") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.rule)
                            .frame(height: 1)
                    }
                    Button {
                        navigation.createBatch(for: row.recipe)
                    } label: {
                        YouCanMakeRow(row: row)
                    }
                    .buttonStyle(HomeRowButtonStyle(isLast: index == rows.count - 1))
                }
            }
        }
    }
}

private struct YouCanMakeRow: View {
    let row: MakeableRecipeRow

    private var accessibilityText: String {
        let trailing = row.isShort ? String(localized: "Short") : row.batchesText
        return [row.recipe.name, row.detail, trailing].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.recipe.name)
                    .font(.body)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
