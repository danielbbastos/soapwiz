import SwiftUI

/// Home's stock that is out, expired, low or about to expire, with what the
/// expiring stock is worth.
struct NeedsAttentionCard: View {
    @Environment(InventoryRows.self) private var inventory
    @Environment(SettingsState.self) private var settings
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.homeNow) private var now

    var body: some View {
        if let attention = NeedsAttention.make(
            ingredients: inventory.ingredients,
            purchases: inventory.purchases,
            tracksInventory: settings.tracksInventory,
            now: now
        ) {
            HomeCard("Needs attention") {
                if attention.valueAtRisk > 0 {
                    header(attention.valueAtRisk)
                }
                ForEach(Array(attention.rows.enumerated()), id: \.element.id) { index, row in
                    let isLast = attention.moreCount == 0 && index == attention.rows.count - 1
                    if index > 0 || attention.valueAtRisk > 0 {
                        divider
                    }
                    Button {
                        navigation.showIngredient(row.ingredient)
                    } label: {
                        rowLabel(row)
                    }
                    .buttonStyle(HomeRowButtonStyle(isLast: isLast))
                }
                if attention.moreCount > 0 {
                    divider
                    Button {
                        navigation.selectedTab = .inventory
                    } label: {
                        Text("\(attention.moreCount) more in Inventory")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.amberText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeRowButtonStyle(isLast: true))
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(height: 1)
    }

    private func header(_ value: Double) -> some View {
        let figure = value.formatted(.currency(code: currencyCode))
        return VStack(alignment: .leading, spacing: 2) {
            Text(figure)
                .font(.system(.title, design: .serif, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.warning)
            Text("of stock expires this month")
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(figure) of stock expires this month"))
    }

    private func rowLabel(_ row: NeedsAttention.Row) -> some View {
        let detail = detailLine(row)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.ingredient.name)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusStamp(word: row.stamp.word, tone: row.stamp.tone, glyph: row.stamp.glyph)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkFaint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.ingredient.name), \(row.stamp.word), \(detail)"))
    }

    private func quantity(_ amount: Double, unit: String) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func detailLine(_ row: NeedsAttention.Row) -> String {
        switch row.reason {
        case .out:
            let left = quantity(0, unit: row.unit)
            if let supplier = row.supplierName {
                return String(localized: "\(left) left · last from \(supplier)")
            }
            return String(localized: "\(left) left")
        case .expired:
            let amount = quantity(row.remaining, unit: row.unit)
            guard let date = row.earliestExpired else { return amount }
            let day = date.formatted(.dateTime.month(.abbreviated).day())
            return String(localized: "\(amount) · expired \(day)")
        case .low:
            let amount = quantity(row.remaining, unit: row.unit)
            guard let threshold = row.lowStockThreshold else {
                return String(localized: "\(amount) left")
            }
            let limit = quantity(threshold, unit: row.unit)
            return String(localized: "\(amount) left · low at \(limit)")
        case .expiring:
            let amount = quantity(row.remaining, unit: row.unit)
            guard row.valueAtRisk > 0 else {
                return String(localized: "\(amount) left")
            }
            let value = row.valueAtRisk.formatted(.currency(code: currencyCode))
            return String(localized: "\(amount) · \(value) at risk")
        }
    }
}
