import SwiftUI

struct SoapPropertyIndicatorView: View {
    let title: String
    let value: Double
    let recommended: ClosedRange<Double>
    let scale: ClosedRange<Double>

    @State private var showingRange = false

    private var status: Status {
        if recommended.contains(value) { .ideal }
        else if value < recommended.lowerBound { .low }
        else { .high }
    }

    private var rangeText: String {
        let lo = recommended.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let hi = recommended.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "\(lo) – \(hi)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title): ")
                    .foregroundStyle(.secondary)
                + Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(status.color)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let total = scale.upperBound - scale.lowerBound
                let bandStart = (recommended.lowerBound - scale.lowerBound) / total * width
                let bandWidth = (recommended.upperBound - recommended.lowerBound) / total * width
                let markerX = max(0, min(width, (value - scale.lowerBound) / total * width))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.18))
                        .frame(height: 8)

                    HStack(spacing: 0) {
                        Color.clear.frame(width: bandStart)
                        Button {
                            showingRange = true
                        } label: {
                            Capsule()
                                .fill(.green.opacity(0.35))
                                .frame(width: bandWidth, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingRange, arrowEdge: .top) {
                            VStack(alignment: .center, spacing: 2) {
                                Text("Recommended")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(rangeText)
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
                        .fill(.tint)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .position(x: markerX, y: 11)
                        .allowsHitTesting(false)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
        }
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
            case .ideal: .green
            case .low: .orange
            case .high: .orange
            }
        }
    }
}
