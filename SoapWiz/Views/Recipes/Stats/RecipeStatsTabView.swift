import SwiftUI

struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel
    @State private var selectedQualityName: String?

    private var selectedQuality: SoapQuality? {
        guard let name = selectedQualityName else { return nil }
        return SoapQuality.allCases.first { $0.displayName == name }
    }

    var body: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts)
        Form {
            propertiesSection(stats)
            fattyAcidSection(stats)
            calculatedValuesSection(stats)
        }
        .scrollClipDisabled()
    }

    private func propertiesSection(_ stats: RecipeStats) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grey bands show the recommended range for each property.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SoapPropertiesChartView(
                    profile: stats.fattyAcidProfile,
                    hasOils: stats.hasOils,
                    selectedDisplayName: $selectedQualityName
                )
            }
            .padding(.vertical, 4)

            if stats.hasOils, let quality = selectedQuality {
                OilContributionCardView(
                    quality: quality,
                    totalValue: quality.value(from: stats.fattyAcidProfile),
                    contributions: stats.contributions(for: quality),
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedQualityName = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if stats.hasOils {
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
        } header: {
            Text("Soap properties")
        }
    }

    @ViewBuilder
    private func fattyAcidSection(_ stats: RecipeStats) -> some View {
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
    private func calculatedValuesSection(_ stats: RecipeStats) -> some View {
        if stats.hasOils {
            Section("Calculated values") {
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
