import SwiftUI
import Charts

struct SoapPropertiesChartView: View {
    let profile: FattyAcidProfile
    let hasOils: Bool
    @Binding var selectedDisplayName: String?

    var body: some View {
        Chart {
            ForEach(SoapQuality.allCases) { quality in
                let range = quality.recommendedRange
                BarMark(
                    x: .value("Quality", quality.displayName),
                    yStart: .value("Min", range.lowerBound),
                    yEnd: .value("Max", range.upperBound),
                    width: .ratio(0.78)
                )
                .foregroundStyle(.gray.opacity(0.18))
                .cornerRadius(4)
            }
            if hasOils {
                ForEach(SoapQuality.allCases) { quality in
                    let value = quality.value(from: profile)
                    BarMark(
                        x: .value("Quality", quality.displayName),
                        y: .value("Score", value),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(quality.color)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text(value, format: .number.precision(.fractionLength(1)))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 20, 40, 60, 80, 100])
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self),
                       let quality = SoapQuality.allCases.first(where: { $0.displayName == name }) {
                        Text(quality.shortName)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let origin = geo[plotFrame].origin
                        let x = location.x - origin.x
                        if let name: String = proxy.value(atX: x) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedDisplayName = (selectedDisplayName == name) ? nil : name
                            }
                        }
                    }
            }
        }
        .frame(height: 260)
    }
}

struct OilContributionCardView: View {
    let quality: SoapQuality
    let totalValue: Double
    let contributions: [OilQualityContribution]
    var onClose: () -> Void

    private var rangeText: String {
        let lo = quality.recommendedRange.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let hi = quality.recommendedRange.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "Recommended: \(lo) – \(hi)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(quality.color)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(quality.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(rangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text(totalValue, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            if contributions.isEmpty {
                Text("No oil in this recipe contributes to \(quality.displayName.lowercased()).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contributions) { row in
                    HStack {
                        Text(row.oilName)
                            .font(.caption)
                        Spacer()
                        Text(row.value, format: .number.precision(.fractionLength(1)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(quality.color.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(quality.color.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    // A background circle masks the border so the button reads as
                    // sitting cleanly on the edge rather than floating over a line.
                    .background(Circle().fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
            // Straddle the top-right corner, centred on the border.
            .offset(x: 9, y: -9)
        }
    }
}
