import SwiftUI

struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel

    var body: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts, makesSoap: model.makesSoap)
        Form {
            if stats.makesSoap {
                propertiesSection(stats)
            }
            fattyAcidSection(stats)
            if stats.makesSoap {
                calculatedValuesSection(stats)
            }
        }
        .scrollClipDisabled()
    }

    private func propertiesSection(_ stats: RecipeStats) -> some View {
        Section {
            SoapPropertiesSection(stats: stats)
        } header: {
            Text("Soap properties")
        }
    }

    /// Shown for both kinds. A non-soap recipe carries the iodine value here,
    /// since it has no Soap properties section to host it.
    ///
    /// The explanation stands in whenever there are ingredients but no profile
    /// among them — on a soap recipe too, where oils entered without one would
    /// otherwise make the whole section disappear rather than say why. A recipe
    /// with no ingredients at all still shows nothing, since there is nothing
    /// yet to explain.
    @ViewBuilder
    private func fattyAcidSection(_ stats: RecipeStats) -> some View {
        if stats.hasFattyAcidData {
            Section("Fatty acid profile") {
                FattyAcidBreakdownRows(stats: stats)
            }
            Section(RecipeStatsCopy.totalsHeader) {
                FattyAcidTotalsRows(stats: stats, showsIodine: !stats.makesSoap)
            }
        } else if stats.hasOils || !stats.makesSoap {
            Section("Fatty acid profile") {
                Text(RecipeStatsCopy.noFattyAcidData)
                    .foregroundStyle(.secondary)
            }
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
