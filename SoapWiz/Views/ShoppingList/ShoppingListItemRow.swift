import SwiftUI

/// One line to buy: a tick, the name, how much, and a note. Tapping the row
/// opens it for editing.
struct ShoppingListItemRow: View {
    @Environment(\.currencyCode) private var currencyCode

    let item: ShoppingListItem
    let lastPurchase: LastPurchase?
    let boughtDate: Date?
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var lastPurchaseLine: String? {
        guard let ingredient = item.ingredient else { return nil }
        return lastPurchase?.line(unit: ingredient.unit, currencyCode: currencyCode)
    }

    private var isDone: Bool {
        item.isChecked || boughtDate != nil
    }

    private var amountText: String? {
        guard let amount = item.amount else { return nil }
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        return item.unit.isEmpty ? number : "\(number) \(item.unit)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            tickButton
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                        .strikethrough(isDone)
                    if let boughtDate {
                        Text("Bought \(boughtDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(Color.amberText)
                    }
                    if let amountText {
                        Text(amountText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.inkSoft)
                    }
                    if let lastPurchaseLine {
                        Text(lastPurchaseLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
        }
        .opacity(isDone ? 0.55 : 1)
    }

    private var tickButton: some View {
        Button(action: onToggle) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? Color.amberText : Color.inkSoft)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(boughtDate != nil)
        .accessibilityLabel(Text(tickLabel))
    }

    private var tickLabel: LocalizedStringKey {
        if boughtDate != nil { return "Bought" }
        return item.isChecked ? "Mark as not bought" : "Mark as bought"
    }
}
