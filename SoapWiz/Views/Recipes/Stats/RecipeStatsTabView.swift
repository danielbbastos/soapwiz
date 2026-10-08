import SwiftUI

/// The recipe form's Stats tab: the same sheets as the recipe detail, then the
/// blend's total SAP values.
struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel

    var body: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts, makesSoap: model.makesSoap)
        Form {
            RecipeDetailStatsSections(stats: stats)
            if stats.makesSoap {
                calculatedValuesSection(stats)
            }
        }
        .readableWidth()
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func calculatedValuesSection(_ stats: RecipeStats) -> some View {
        if stats.hasOils, let naoh = stats.totalNaOHSap, let koh = stats.totalKOHSap {
            Section {
                statRow("Total NaOH SAP", value: naoh, fractionDigits: 4)
                    .ledgerSheetRow(position: .first)
                statRow("Total KOH SAP", value: koh, fractionDigits: 4)
                    .ledgerSheetRow(position: .last)
            } header: {
                HoneyLedgerSectionLabel("Calculated values")
            }
        }
    }

    private func statRow(_ label: String, value: Double, fractionDigits: Int) -> some View {
        HoneyLedgerLabeledRow(label) {
            Text(value, format: .number.precision(.fractionLength(fractionDigits)))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }
}
