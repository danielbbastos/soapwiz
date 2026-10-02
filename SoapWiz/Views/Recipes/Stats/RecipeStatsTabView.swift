import SwiftUI

struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel

    var body: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts, makesSoap: model.makesSoap)
        Form {
            if stats.makesSoap {
                propertiesSection(stats)
            }
            FattyAcidProfileSections(stats: stats)
            if stats.makesSoap {
                calculatedValuesSection(stats)
            }
        }
        .readableWidth()
        .scrollClipDisabled()
    }

    private func propertiesSection(_ stats: RecipeStats) -> some View {
        Section {
            SoapPropertiesSection(stats: stats)
        } header: {
            Text("Soap properties")
        }
    }

    @ViewBuilder
    private func calculatedValuesSection(_ stats: RecipeStats) -> some View {
        if stats.hasOils, let naoh = stats.totalNaOHSap, let koh = stats.totalKOHSap {
            Section("Calculated values") {
                statRow("Total NaOH SAP", value: naoh, fractionDigits: 4)
                statRow("Total KOH SAP", value: koh, fractionDigits: 4)
            }
        }
    }

    private func statRow(_ label: String, value: Double, fractionDigits: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(fractionDigits)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

}
