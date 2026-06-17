import SwiftUI

struct PurchaseRowView: View {
    let purchase: IngredientPurchase
    let unit: String

    private var expiryLabel: (text: String, color: Color)? {
        guard let expiry = purchase.expiryDate else { return nil }
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
                Text(purchase.provider?.name ?? "Unknown Provider")
                    .font(.headline)
                Spacer()
                if let label = expiryLabel {
                    Text(label.text)
                        .font(.caption)
                        .foregroundStyle(label.color)
                }
            }
            HStack {
                let remaining = purchase.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))
                let quantity = purchase.quantity.formatted(.number.precision(.fractionLength(0...2)))
                Text("\(remaining) / \(quantity) \(unit)")
                    .font(.subheadline)
                    .foregroundStyle(purchase.remainingAmount > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                Spacer()
                if !purchase.badge.isEmpty {
                    Text(purchase.badge)
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
