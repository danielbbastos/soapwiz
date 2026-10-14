import SwiftUI

/// The recipe form's Stats tab: the same sheets as the recipe detail, then the
/// blend's total SAP values.
struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel

    /// The rows the stats are computed from. They trail `model.oilDrafts` while
    /// an amount is being typed, so the chart doesn't animate through every
    /// intermediate value.
    @State private var shownDrafts: [OilIngredientDraft]?

    var body: some View {
        let stats = RecipeStats(oilDrafts: shownDrafts ?? model.oilDrafts, makesSoap: model.makesSoap)
        Form {
            RecipeDetailStatsSections(stats: stats, chartTourAnchor: .qualityBars)
            if stats.makesSoap {
                calculatedValuesSection(stats)
            }
        }
        .readableWidth()
        .scrollClipDisabled()
        .task(id: model.oilDrafts) {
            if RecipeStatsRefresh.updatesImmediately(from: shownDrafts, to: model.oilDrafts) {
                shownDrafts = model.oilDrafts
                return
            }
            // Each edit cancels this task, so only the last one gets past the sleep.
            try? await Task.sleep(for: RecipeStatsRefresh.delay)
            if Task.isCancelled { return }
            shownDrafts = model.oilDrafts
        }
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
