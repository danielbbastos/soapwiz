import SwiftUI

struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel

    private var stats: RecipeStats {
        RecipeStats(oilDrafts: model.oilDrafts)
    }

    var body: some View {
        Form {
            propertiesSection
            indicatorsSection
            fattyAcidSection
            calculatedValuesSection
        }
        .scrollClipDisabled()
    }

    private var propertiesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grey bands show the recommended range for each property.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SoapPropertiesChartView(profile: stats.fattyAcidProfile, hasOils: stats.hasOils)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Soap properties")
        }
    }

    @ViewBuilder
    private var indicatorsSection: some View {
        if stats.hasOils {
            Section {
                SoapPropertyIndicatorView(
                    title: "INS",
                    value: stats.ins,
                    recommended: SoapMetric.insRange,
                    scale: SoapMetric.insScale
                )
                SoapPropertyIndicatorView(
                    title: "Iodine",
                    value: stats.iodineValue,
                    recommended: SoapMetric.iodineRange,
                    scale: SoapMetric.iodineScale
                )
            }
        }
    }

    @ViewBuilder
    private var fattyAcidSection: some View {
        if stats.hasOils {
            Section("Fatty acid profile") {
                fattyAcidRow("Lauric", stats.fattyAcidProfile.lauric)
                fattyAcidRow("Myristic", stats.fattyAcidProfile.myristic)
                fattyAcidRow("Palmitic", stats.fattyAcidProfile.palmitic)
                fattyAcidRow("Stearic", stats.fattyAcidProfile.stearic)
                fattyAcidRow("Oleic", stats.fattyAcidProfile.oleic)
                fattyAcidRow("Linoleic", stats.fattyAcidProfile.linoleic)
                fattyAcidRow("Linolenic", stats.fattyAcidProfile.linolenic)
                fattyAcidRow("Ricinoleic", stats.fattyAcidProfile.ricinoleic)
                Divider()
                fattyAcidRow("Saturated", stats.fattyAcidProfile.saturated, emphasis: true)
                fattyAcidRow("Mono-unsaturated", stats.fattyAcidProfile.monoUnsaturated, emphasis: true)
                fattyAcidRow("Poly-unsaturated", stats.fattyAcidProfile.polyUnsaturated, emphasis: true)
            }
        }
    }

    @ViewBuilder
    private var calculatedValuesSection: some View {
        if stats.hasOils {
            Section("Calculated values") {
                statRow("Iodine value", value: stats.iodineValue, fractionDigits: 1)
                statRow("INS", value: stats.ins, fractionDigits: 1)
                statRow("Total NaOH SAP", value: stats.totalNaOHSap, fractionDigits: 4)
                statRow("Total KOH SAP", value: stats.totalKOHSap, fractionDigits: 4)
            }
        }
    }

    private func fattyAcidRow(_ label: String, _ value: Double, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .fontWeight(emphasis ? .semibold : .regular)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
                .foregroundStyle(emphasis ? .primary : .secondary)
            Text("%")
                .foregroundStyle(.secondary)
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
