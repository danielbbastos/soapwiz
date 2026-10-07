import SwiftUI

/// The rows of the ingredient detail's Summary section, each drawing its share
/// of the ledger sheet from where it sits among the rows actually shown.
struct IngredientDetailSummaryRows: View {
    let ingredient: Ingredient
    let totalRemaining: Double
    let tracksInventory: Bool
    let showsChemistry: Bool

    private enum Row: Hashable {
        case category(String)
        case unit(String)
        case totalRemaining
        case purchases
        case sap(Double)
        case density
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let categoryName = ingredient.category?.name {
            rows.append(.category(categoryName))
        }
        if !ingredient.unit.isEmpty {
            rows.append(.unit(IngredientUnit(rawValue: ingredient.unit)?.label ?? ingredient.unit))
        }
        if tracksInventory {
            rows.append(.totalRemaining)
            rows.append(.purchases)
        }
        // Oils carry SAP in the dedicated chemistry block below; this
        // is the fallback for the rare non-oil that still has a value.
        if !showsChemistry, let sap = ingredient.sapValue {
            rows.append(.sap(sap))
        }
        if IngredientUnitConverter.isVolume(ingredient.unit) {
            rows.append(.density)
        }
        return rows
    }

    var body: some View {
        let rows = rows
        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
            rowView(row)
                .ledgerSheetRow(position: .position(index: index, count: rows.count))
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .category(let name):
            HoneyLedgerLabeledRow("Category") { Text(name).font(.body).foregroundStyle(Color.ink) }
        case .unit(let label):
            HoneyLedgerLabeledRow("Unit") { Text(label).font(.body).foregroundStyle(Color.ink) }
        case .totalRemaining:
            let isOut = totalRemaining <= 0
            HoneyLedgerLabeledRow("Total Remaining") {
                HStack(spacing: 8) {
                    if isOut {
                        let out = IngredientStockStamp.out
                        StatusStamp(word: out.word, tone: out.tone, glyph: out.glyph)
                    }
                    Text.honeyLedgerFigure(
                        totalRemaining.formatted(.number.precision(.fractionLength(0...2))),
                        unit: ingredient.unit,
                        numberColor: isOut ? .danger : .ink
                    )
                }
            }
        case .purchases:
            HoneyLedgerLabeledRow("Purchases") {
                Text.honeyLedgerFigure("\(ingredient.purchases.count)")
            }
        case .sap(let sap):
            HoneyLedgerLabeledRow("SAP Value (NaOH)") {
                Text.honeyLedgerFigure(
                    sap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                    unit: "g/g"
                )
            }
        case .density:
            let stored = ingredient.density
            let value = stored ?? IngredientUnitConverter.defaultDensity
            let source = stored == nil ? "default" : "custom"
            HoneyLedgerLabeledRow("Density") {
                Text.honeyLedgerFigure(
                    value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                    unit: "g/ml (\(source))"
                )
            }
        }
    }
}
