import SwiftUI

/// An ingredient worth buying, with why and where it was last bought.
struct ShoppingSuggestionRow: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let suggestion: ShoppingSuggestion
    let onAdd: () -> Void

    private var stamps: [IngredientStockStamp] {
        suggestion.reasons.map { reason in
            switch reason {
            case .out: .out
            case .expired: .expired
            case .low: .low
            case .expiring(let days): .expiresIn(days: days)
            }
        }
    }

    private var lastBoughtLine: String? {
        suggestion.lastPurchase.line(unit: suggestion.unit, currencyCode: currencyCode)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    addButton
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    details
                    addButton
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.ingredient.name)
                .font(.headline)
                .foregroundStyle(Color.ink)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { stampViews }
                VStack(alignment: .leading, spacing: 4) { stampViews }
            }
            if let lastBoughtLine {
                Text(lastBoughtLine)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stampViews: some View {
        ForEach(stamps, id: \.word) { stamp in
            StatusStamp(word: stamp.word, tone: stamp.tone, glyph: stamp.glyph)
        }
    }

    private var addButton: some View {
        Button("Add", action: onAdd)
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
            .foregroundStyle(Color.amberText)
            .accessibilityLabel(Text("Add \(suggestion.ingredient.name)"))
    }
}
