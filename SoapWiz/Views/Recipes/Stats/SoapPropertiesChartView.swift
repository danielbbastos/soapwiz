import SwiftUI
import Charts

struct SoapPropertiesChartView: View {
    let profile: FattyAcidProfile
    let hasOils: Bool

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
        .frame(height: 260)
    }
}
