import SwiftUI
import SwiftData

/// The "Cost breakdown" section of a recipe's detail screen: the whole-batch
/// total with RRP, plus an expandable per-product cost breakdown. Reads its
/// figures from the view model and the app's RRP factor from settings.
struct RecipeCostSection: View {
    let model: RecipeFormViewModel
    let batch: ProductCostBreakdown
    /// `true` renders a free-standing `RecipeDetailCard` for the wide
    /// side-by-side layout instead of a Form section.
    var asCard = false

    @Query private var settingsRecords: [AppSettings]
    @State private var batchTotalExpanded = true
    @State private var expandedProducts: [PersistentIdentifier: Bool] = [:]

    /// One titled group of breakdown rows (Oils / Additives / Fragrances / Lye).
    private struct CostGroup {
        let name: String
        let usesEnteredUnit: Bool
        let rows: [IngredientProductBreakdown]
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var pvpFactor: Double { settingsRecords.first?.pvpFactor ?? 4.0 }

    var body: some View {
        if asCard {
            RecipeDetailCard(title: "Cost breakdown") {
                content
            }
        } else {
            Section("Cost breakdown") {
                content
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            let batchTotal = batch.total
            if batchTotal > 0 {
                DisclosureGroup(isExpanded: $batchTotalExpanded) {
                    productBreakdownRows(batch)
                } label: {
                    HStack {
                        Text("Batch total")
                            .fontWeight(.semibold)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatCurrency(batchTotal))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("RRP \(formatCurrency(batchTotal * pvpFactor))")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("No cost data — add purchase prices in Inventory")
                    .foregroundStyle(.secondary)
            }

            let breakdowns = productBreakdowns(batch: batch)
            ForEach(nonWholeBatchProducts, id: \.id) { draft in
                if let modelID = draft.modelID, let breakdown = breakdowns[draft.id], breakdown.total > 0 {
                    DisclosureGroup(isExpanded: isExpanded(modelID: modelID)) {
                        productBreakdownRows(breakdown)
                    } label: {
                        productDisclosureLabel(draft, breakdown: breakdown)
                    }
                }
            }
        }
    }

    private var nonWholeBatchProducts: [RecipeProductDraft] {
        model.productDrafts.filter { draft in
            let unit = ProductUnit(rawValue: draft.unitSymbol)
            if unit == .wholeBatch { return false }
            if unit == .partsOfBatch && draft.size <= 1 { return false }
            return true
        }
    }

    private func productBreakdowns(batch: ProductCostBreakdown) -> [UUID: ProductCostBreakdown] {
        Dictionary(uniqueKeysWithValues: nonWholeBatchProducts.map { draft in
            (draft.id, model.breakdownAndCost(for: draft, batch: batch))
        })
    }

    private func isExpanded(modelID: PersistentIdentifier) -> Binding<Bool> {
        Binding(
            get: { expandedProducts[modelID] ?? false },
            set: { expandedProducts[modelID] = $0 }
        )
    }

    private func productLabel(_ draft: RecipeProductDraft) -> String {
        guard let unit = ProductUnit(rawValue: draft.unitSymbol) else {
            return draft.unitSymbol
        }
        if unit == .partsOfBatch {
            return "1/\(Int(draft.size)) batch"
        }
        let sizeFmt = Self.amountFormatter.string(from: NSNumber(value: draft.size)) ?? "\(draft.size)"
        return "\(sizeFmt) \(draft.unitSymbol)"
    }

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit)"
    }

    private func productDisclosureLabel(_ draft: RecipeProductDraft, breakdown: ProductCostBreakdown) -> some View {
        HStack {
            Text(productLabel(draft))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCurrency(breakdown.total))
                    .font(.subheadline)
                    .monospacedDigit()
                Text("RRP \(formatCurrency(breakdown.total * pvpFactor))")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }
        }
    }

    private func productBreakdownRows(_ breakdown: ProductCostBreakdown) -> some View {
        let groups: [CostGroup] = [
            CostGroup(name: "Oils", usesEnteredUnit: false, rows: breakdown.oils),
            CostGroup(name: "Additives", usesEnteredUnit: true, rows: breakdown.additives),
            CostGroup(name: "Fragrances", usesEnteredUnit: true, rows: breakdown.fragrances),
            CostGroup(name: "Lye", usesEnteredUnit: false, rows: breakdown.lye)
        ].filter { !$0.rows.isEmpty }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.name) { group in
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(group.rows, id: \.ingredient.persistentModelID) { row in
                    let display = model.displayedAmount(for: row, usesEnteredUnit: group.usesEnteredUnit)
                    HStack(spacing: 8) {
                        Text(row.ingredient.name)
                            .font(.footnote)
                        Spacer()
                        if let note = display.conversionNote {
                            InfoPopoverIcon(text: note)
                        }
                        Text(amountText(display.amount, unit: display.unit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if row.cost > 0 {
                            Text(formatCurrency(row.cost))
                                .font(.footnote)
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }
}
