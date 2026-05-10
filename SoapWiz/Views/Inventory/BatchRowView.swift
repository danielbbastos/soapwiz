import SwiftUI

struct BatchRowView: View {
    let batch: IngredientBatch
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(batch.provider.isEmpty ? "Unknown Provider" : batch.provider)
                    .font(.headline)
                Spacer()
                Text(batch.dateOfPurchase, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
