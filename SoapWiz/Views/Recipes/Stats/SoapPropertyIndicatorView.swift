import SwiftUI

struct SoapPropertyIndicatorView: View {
    let title: String
    let value: Double
    let recommended: ClosedRange<Double>
    let scale: ClosedRange<Double>

    private var status: Status {
        if recommended.contains(value) { .ideal }
        else if value < recommended.lowerBound { .low }
        else { .high }
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
                    Capsule()
                        .fill(.green.opacity(0.35))
                        .frame(width: bandWidth, height: 8)
                        .offset(x: bandStart)
                    Circle()
                        .fill(.tint)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .offset(x: markerX - 7)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
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
