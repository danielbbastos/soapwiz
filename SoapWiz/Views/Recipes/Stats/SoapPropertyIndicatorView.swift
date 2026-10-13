import SwiftUI

struct SoapPropertyIndicatorView: View {
    let title: String
    let value: Double
    let recommended: ClosedRange<Double>
    let scale: ClosedRange<Double>
    var infoTitle: String?
    var infoText: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingRange = false

    private var status: Status {
        if recommended.contains(value) {
            .ideal
        } else if value < recommended.lowerBound {
            .low
        } else {
            .high
        }
    }

    /// A range in whole numbers, for the popover and for VoiceOver.
    static func rangeText(_ range: ClosedRange<Double>) -> String {
        let low = range.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let high = range.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "\(low) to \(high)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Two lines at the accessibility sizes: beside the info icon and the
            // status, the title would be squeezed until it broke mid-figure.
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text(title)
                        .foregroundStyle(Color.inkSoft)
                    infoIcon
                }
                HStack {
                    valueText
                    Spacer()
                    statusLabel
                }
            } else {
                HStack {
                    Text("\(title): ")
                        .foregroundStyle(Color.inkSoft)
                    + valueText
                    // A sibling of the concatenation rather than part of it: a view
                    // can't join a `Text` + `Text` chain.
                    infoIcon
                    Spacer()
                    statusLabel
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                let total = scale.upperBound - scale.lowerBound
                let bandStart = (recommended.lowerBound - scale.lowerBound) / total * width
                let bandWidth = (recommended.upperBound - recommended.lowerBound) / total * width
                let markerX = max(0, min(width, (value - scale.lowerBound) / total * width))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.chartBand)
                        .frame(height: 8)

                    HStack(spacing: 0) {
                        Color.clear.frame(width: bandStart)
                        Button {
                            showingRange = true
                        } label: {
                            Capsule()
                                .fill(Color.success.opacity(0.35))
                                .frame(width: bandWidth, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingRange, arrowEdge: .top) {
                            VStack(alignment: .center, spacing: 2) {
                                Text("Recommended")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(Self.rangeText(recommended))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .presentationCompactAdaptation(.popover)
                        }
                        Spacer(minLength: 0)
                    }

                    Circle()
                        .fill(Color.amber)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.paperRaised, lineWidth: 2))
                        .position(x: markerX, y: 11)
                        // Keyed on value so rotation and first appearance don't glide.
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
                        .allowsHitTesting(false)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
        }
    }

    private var valueText: Text {
        Text(value, format: .number.precision(.fractionLength(1)))
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
    }

    @ViewBuilder
    private var infoIcon: some View {
        if let infoText {
            InfoPopoverIcon(title: infoTitle, text: infoText)
        }
    }

    private var statusLabel: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.18), in: Capsule())
            .foregroundStyle(status.color)
    }

    private enum Status {
        case ideal, low, high

        var label: String {
            switch self {
            case .ideal: "Ideal"
            case .low: "Low"
            case .high: "High"
            }
        }

        var color: Color {
            switch self {
            case .ideal: .success
            case .low: .warning
            case .high: .warning
            }
        }
    }
}
