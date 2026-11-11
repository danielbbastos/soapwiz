import SwiftUI

/// Home's shopping list: how much is left to buy and how much more the stock
/// suggests, opening the list. Pro only; anyone else sees nothing.
struct ShoppingListCard: View {
    @Environment(ShoppingListRows.self) private var shoppingList
    @Environment(InventoryRows.self) private var inventory
    @Environment(SettingsState.self) private var settings
    @Environment(\.homeNow) private var now
    @FreeTierGateEnvironment private var freeTier

    @State private var isPresented = false

    var body: some View {
        if freeTier.gate.allows(.shoppingList), let summary = visibleSummary {
            HomeCard("Shopping list") {
                Button {
                    isPresented = true
                } label: {
                    rowLabel(summary)
                }
                .buttonStyle(HomeRowButtonStyle(isLast: true))
            }
            .shoppingListSheet(
                isPresented: $isPresented,
                ingredients: inventory.ingredients,
                purchases: inventory.purchases,
                tracksInventory: settings.tracksInventory
            )
        }
    }

    /// Kept on screen while the sheet is open, so clearing the list from inside
    /// it doesn't remove the card, and the sheet with it.
    private var visibleSummary: HomeShoppingList.Summary? {
        let summary = HomeShoppingList.make(
            items: shoppingList.items,
            ingredients: inventory.ingredients,
            purchases: inventory.purchases,
            tracksInventory: settings.tracksInventory,
            now: now
        )
        if let summary { return summary }
        return isPresented ? HomeShoppingList.Summary(toBuyCount: 0, suggestedCount: 0) : nil
    }

    private func rowLabel(_ summary: HomeShoppingList.Summary) -> some View {
        let title = title(for: summary)
        let subtitle = subtitle(for: summary)
        return HStack(spacing: 12) {
            Image(systemName: "cart")
                .font(.title2)
                .foregroundStyle(Color.inkSoft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkFaint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(subtitle.map { "\(title), \($0)" } ?? title))
    }

    private func title(for summary: HomeShoppingList.Summary) -> String {
        guard summary.toBuyCount > 0 else { return String(localized: "Nothing to buy") }
        return String(localized: "\(summary.toBuyCount) to buy")
    }

    private func subtitle(for summary: HomeShoppingList.Summary) -> String? {
        guard summary.suggestedCount > 0 else { return nil }
        if summary.toBuyCount > 0 {
            return String(localized: "\(summary.suggestedCount) more suggested from stock")
        }
        return String(localized: "\(summary.suggestedCount) suggested from stock")
    }
}
