import SwiftUI

struct PurchaseRowView: View {
    let purchase: IngredientPurchase
    let unit: String

    private func statusText(for summary: PurchaseRowSummary) -> String? {
        switch summary.status {
        case .none: nil
        case .usedUp: String(localized: "used up")
        case .expired: String(localized: "expired")
        case .expires(let date):
            String(localized: "expires \(date.formatted(.dateTime.month(.abbreviated).year()))")
        }
    }

    private func secondLine(for summary: PurchaseRowSummary) -> String {
        let date = purchase.dateOfPurchase.formatted(.dateTime.day().month(.abbreviated).year())
        guard let statusText = statusText(for: summary) else { return date }
        return "\(date) · \(statusText)"
    }

    private var remainingText: Text {
        let number = purchase.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))
        if purchase.remainingAmount <= 0 {
            return Text.honeyLedgerFigure(number, unit: unit, numberColor: .inkFaint, unitColor: .inkFaint)
        }
        return Text.honeyLedgerFigure(number, unit: unit)
    }

    var body: some View {
        let summary = PurchaseRowSummary(
            expiryDate: purchase.expiryDate,
            remainingAmount: purchase.remainingAmount,
            badge: purchase.badge
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.provider?.name ?? "Unknown Provider")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text(secondLine(for: summary))
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer(minLength: 8)
                remainingText
            }
            if !summary.stamps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(summary.stamps.enumerated()), id: \.offset) { _, stamp in
                        StatusStamp(word: stamp.word, tone: stamp.tone, glyph: stamp.glyph)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
