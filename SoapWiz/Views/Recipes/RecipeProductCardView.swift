import SwiftUI

/// One size's ingredient lines in the cost breakdown bar, grouped under small
/// headings, with space rather than rules between the groups. Tapping a group
/// folds its lines into one subtotal line. The size's own header sits in the
/// bar's header (`RecipeProductHeaderView`).
struct RecipeProductCardView: View {
    @Environment(\.currencyCode) private var currencyCode
    let breakdown: ProductCostBreakdown
    let model: RecipeFormViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .subheadline) private var compactColumnWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var regularColumnWidth: CGFloat = 88
    @State private var collapsedGroups: Set<BreakdownGroupKey> = []

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var lineFont: Font { isRegular ? .body : .subheadline }
    private var columnWidth: CGFloat { isRegular ? regularColumnWidth : compactColumnWidth }

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var groups: [(key: BreakdownGroupKey, rows: [IngredientProductBreakdown])] {
        BreakdownGroupKey.groups(of: breakdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.key) { index, group in
                groupView(key: group.key, rows: group.rows, isFirst: index == 0)
            }
        }
        .padding(.horizontal, isRegular ? 20 : 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func groupView(key: BreakdownGroupKey, rows: [IngredientProductBreakdown], isFirst: Bool) -> some View {
        let isCollapsed = collapsedGroups.contains(key)
        return Button {
            if isCollapsed { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(key.displayName)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(Color.inkSoft)
                    .padding(.top, isFirst ? 4 : 14)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                if isCollapsed {
                    subtotalLine(rows: rows)
                        .transition(.identity)
                } else {
                    ForEach(rows, id: \.ingredient.persistentModelID) { row in
                        let display = model.displayedAmount(for: row, usesEnteredUnit: key.usesEnteredUnit)
                        line(
                            name: row.ingredient.name,
                            amount: display.amount,
                            unit: display.unit,
                            cost: row.cost,
                            note: display.conversionNote
                        )
                    }
                    .transition(.identity)
                }
            }
            .animation(nil, value: isCollapsed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
    }

    private func subtotalLine(rows: [IngredientProductBreakdown]) -> some View {
        // Collapsed group total uses the oil weight unit, since rows may mix units.
        let totalAmount = rows.reduce(0) { $0 + $1.ingredientAmount }
        let totalCost = rows.reduce(0) { $0 + $1.cost }
        return line(
            name: String(localized: "Subtotal"), amount: totalAmount, unit: model.displayWeightUnit,
            cost: totalCost, emphasized: true
        )
    }

    /// Name, amount and cost in three columns, the two figures right-aligned
    /// so they line up down the page.
    private func line(
        name: String, amount: Double, unit: String, cost: Double,
        emphasized: Bool = false, note: String? = nil
    ) -> some View {
        let weight: Font.Weight = emphasized ? .semibold : .regular
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 2) {
                Text(name)
                    .fontWeight(weight)
                    .foregroundStyle(Color.ink)
                if let note {
                    InfoPopoverIcon(text: note)
                        .padding(.vertical, -6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Self.amountFormatter.string(from: NSNumber(value: amount)) ?? "") \(unit)")
                .foregroundStyle(Color.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: columnWidth, alignment: .trailing)
            // A price-less ingredient shows a dash where its price would be.
            Text(cost > 0 ? cost.formatted(.currency(code: currencyCode)) : "—")
                .fontWeight(weight)
                .foregroundStyle(cost > 0 ? Color.ink : Color.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: columnWidth, alignment: .trailing)
        }
        .font(lineFont)
        .monospacedDigit()
        .padding(.vertical, isRegular ? 4 : 3)
    }
}

struct AddProductCardView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add size", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .frame(maxWidth: .infinity, minHeight: 80)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
