import SwiftUI

struct BatchRowView: View {
    let batch: IngredientBatch
    let unit: String

    private var expiryLabel: (text: String, color: Color)? {
        guard let expiry = batch.expiryDate else { return nil }
        let now = Date.now
        let formatted = expiry.formatted(.dateTime.day().month(.abbreviated).year())
        if expiry < now {
            return ("Expired", .red)
        }
        if let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: now), expiry <= cutoff {
            return (formatted, .red)
        }
        return (formatted, .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(batch.provider?.name ?? "Unknown Provider")
                    .font(.headline)
                Spacer()
                if let label = expiryLabel {
                    Text(label.text)
                        .font(.caption)
                        .foregroundStyle(label.color)
                }
            }
            HStack {
                Text("\(batch.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))) / \(batch.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                    .font(.subheadline)
                    .foregroundStyle(batch.remainingAmount > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                Spacer()
                if !batch.badge.isEmpty {
                    Text(batch.badge)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
