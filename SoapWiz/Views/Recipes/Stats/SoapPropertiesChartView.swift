import SwiftUI
import Charts

struct SoapPropertiesChartView: View {
    let profile: FattyAcidProfile
    let hasOils: Bool
    @Binding var selectedDisplayName: String?

    /// When false the chart is a static read-out: the tap overlay is dropped, so
    /// bars can't be selected. See `SoapPropertiesSection.interactive`.
    var interactive: Bool = true

    @State private var plotWidth: CGFloat = 0
    @State private var fullNameWidth: CGFloat = 0

    private static let labelGap: CGFloat = 8

    // Measured from the plot itself so narrow sheets and split views fall back to short names.
    static func showsFullNames(plotWidth: CGFloat, fullNameWidth: CGFloat, count: Int, gap: CGFloat) -> Bool {
        guard plotWidth > 0, fullNameWidth > 0, count > 0 else { return false }
        return plotWidth / CGFloat(count) >= fullNameWidth + gap
    }

    private var showsFullNames: Bool {
        Self.showsFullNames(
            plotWidth: plotWidth,
            fullNameWidth: fullNameWidth,
            count: SoapQuality.allCases.count,
            gap: Self.labelGap
        )
    }

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
                .foregroundStyle(Color.chartBand)
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
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
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
                        Text(showsFullNames ? quality.displayName : quality.shortName)
                            .font(.caption2)
                            .fixedSize(horizontal: showsFullNames, vertical: false)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onChange(of: proxy.plotFrame.map { geo[$0].width } ?? 0, initial: true) { _, width in
                        plotWidth = width
                    }
                    .onTapGesture { location in
                        guard interactive else { return }
                        guard let plotFrame = proxy.plotFrame else { return }
                        let origin = geo[plotFrame].origin
                        let xPosition = location.x - origin.x
                        if let name: String = proxy.value(atX: xPosition) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedDisplayName = (selectedDisplayName == name) ? nil : name
                            }
                        }
                    }
            }
        }
        .frame(height: 260)
        .background {
            VStack {
                ForEach(SoapQuality.allCases) { quality in
                    Text(quality.displayName)
                        .font(.caption2)
                        .fixedSize()
                }
            }
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullNameWidth = $0 }
        }
    }
}

struct OilContributionCardView: View {
    let quality: SoapQuality
    let totalValue: Double
    let contributions: [OilQualityContribution]
    var onClose: () -> Void

    private var rangeText: String {
        let low = quality.recommendedRange.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let high = quality.recommendedRange.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "Recommended: \(low) – \(high)"
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
                        .foregroundStyle(Color.ink)
                    Text(rangeText)
                        .font(.caption2)
                        .foregroundStyle(Color.inkSoft)
                        .monospacedDigit()
                }
                Spacer()
                Text(totalValue, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
            }

            if contributions.isEmpty {
                Text("No oil in this recipe contributes to \(quality.displayName.lowercased()).")
                    .font(.caption)
                    .foregroundStyle(Color.inkSoft)
            } else {
                ForEach(contributions) { row in
                    HStack {
                        Text(row.oilName)
                            .font(.caption)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text(row.value, format: .number.precision(.fractionLength(1)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.inkSoft)
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
                    .foregroundStyle(Color.inkSoft)
                    // A background circle masks the border so the button reads as
                    // sitting cleanly on the edge rather than floating over a line.
                    .background(Circle().fill(Color.paperRaised))
            }
            .buttonStyle(.plain)
            // Straddle the top-right corner, centred on the border.
            .offset(x: 9, y: -9)
        }
    }
}
