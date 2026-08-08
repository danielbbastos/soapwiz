import SwiftUI

/// The soap-properties block shared by the recipe form's Stats tab and the
/// recipe detail screen: the qualities chart, the drill-down card for the
/// selected quality, and the INS / iodine indicators. Emits rows rather than a
/// `Section` so each call site keeps its own header and row background.
struct SoapPropertiesSection: View {
    let stats: RecipeStats

    @State private var selectedQualityName: String?

    private var selectedQuality: SoapQuality? {
        guard let name = selectedQualityName else { return nil }
        return SoapQuality.allCases.first { $0.displayName == name }
    }

    var body: some View {
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
    }
}
