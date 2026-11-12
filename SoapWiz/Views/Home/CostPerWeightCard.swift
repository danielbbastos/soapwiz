import SwiftData
import SwiftUI

/// Insights' cost card: what each recipe cost per kilogram or pound over the
/// past year, dearest first, as a figure and a bar against the dearest.
struct CostPerWeightCard: View {
    @Environment(BatchRows.self) private var batchRows
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.homeNow) private var now
    @Environment(\.locale) private var locale
    @Environment(\.currencyCode) private var currencyCode

    var body: some View {
        let unit = CostWeightUnit.preferred(for: locale)
        let costs = RecipeCostPerWeight(batches: batchRows.batches, now: now, unit: unit)
        VStack(alignment: .leading, spacing: 12) {
            header(unit)
            if costs.isEmpty {
                Text("Costs show here once a batch with prices and a weight is made.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            } else {
                ForEach(costs.rows) { row in
                    if let recipe = row.recipe {
                        Button {
                            navigation.pushOnHome(recipe)
                        } label: {
                            CostRowView(row: row, unit: unit, currencyCode: currencyCode)
                        }
                        .buttonStyle(HomeRowButtonStyle(isLast: false))
                    } else {
                        CostRowView(row: row, unit: unit, currencyCode: currencyCode)
                    }
                }
                Text("Batch cost divided by its recorded weight. Batches without a weight are left out.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerSheet()
    }

    private func header(_ unit: CostWeightUnit) -> some View {
        let title = Text("Cost per \(unit.symbol)")
            .font(.title3.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(Color.ink)
        let period = Text(" · past year")
            .font(.subheadline)
            .foregroundStyle(Color.inkSoft)
        return (title + period)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CostRowView: View {
    let row: RecipeCostRow
    let unit: CostWeightUnit
    let currencyCode: String

    private var amount: String {
        row.costPerUnit.formatted(.currency(code: currencyCode))
    }

    private var unitName: String {
        switch unit {
        case .kilogram: String(localized: "kilogram")
        case .pound: String(localized: "pound")
        }
    }

    var body: some View {
        let name = Text(verbatim: row.name)
            .font(.subheadline)
            .foregroundStyle(Color.ink)
        let figure = Text(verbatim: "\(amount)/\(unit.symbol)")
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer(minLength: 8)
                    figure
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    figure
                }
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.heatmapLevel(0))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.pigmentWalnut)
                            .frame(width: proxy.size.width * row.fraction)
                    }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.name), \(amount) per \(unitName)"))
    }
}

#if DEBUG
#Preview("Cost, phone") {
    let data = BatchHeatmapPreviewData()
    CostPerWeightCard()
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}

#Preview("Cost, iPad", traits: .fixedLayout(width: 420, height: 420)) {
    let data = BatchHeatmapPreviewData()
    CostPerWeightCard()
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
        .environment(\.locale, Locale(identifier: "en_US"))
}

#Preview("Cost, empty") {
    let data = BatchHeatmapPreviewData(batchCount: 6, weighted: false)
    CostPerWeightCard()
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}
#endif
