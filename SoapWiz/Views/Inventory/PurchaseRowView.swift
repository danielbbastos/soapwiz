import SwiftUI

struct PurchaseRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout(summary: summary)
            } else {
                standardLayout(summary: summary)
            }
        }
        .padding(.vertical, 2)
    }

    private func standardLayout(summary: PurchaseRowSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                names(summary: summary)
                Spacer(minLength: 8)
                remainingText
            }
            stampLine(summary.stamps)
        }
    }

    /// One column at the accessibility sizes: beside the quantity, the provider
    /// would be squeezed until it broke mid-word.
    private func accessibilityLayout(summary: PurchaseRowSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            names(summary: summary)
            stampLine(summary.stamps)
            remainingText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func names(summary: PurchaseRowSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(purchase.provider?.name ?? "Unknown Provider")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
            Text(secondLine(for: summary))
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
    }

    /// The stamps side by side, stacking when they don't fit.
    @ViewBuilder
    private func stampLine(_ stamps: [PurchaseRowStamp]) -> some View {
        if !stamps.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { stampViews(stamps) }
                VStack(alignment: .leading, spacing: 4) { stampViews(stamps) }
            }
        }
    }

    private func stampViews(_ stamps: [PurchaseRowStamp]) -> some View {
        ForEach(Array(stamps.enumerated()), id: \.offset) { _, stamp in
            StatusStamp(word: stamp.word, tone: stamp.tone, glyph: stamp.glyph)
        }
    }
}
