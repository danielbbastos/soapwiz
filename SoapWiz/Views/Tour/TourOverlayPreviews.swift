import SwiftUI

/// A stand-in for a real screen, with the controls the tour points at tagged.
struct TourPreviewScreen: View {
    var wide = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(verbatim: "Search ingredients")
                    Spacer()
                }
                .foregroundStyle(Color.inkSoft)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .ledgerRaisedSurface(in: Capsule())
                .tourAnchor(.inventorySearch, cornerRadius: 26)
                fakeRow("Olive oil")
                fakeRow("Coconut oil")
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Shea butter").font(.headline)
                    Text(verbatim: "3 purchases, 1.2 kg left").foregroundStyle(Color.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                .padding(.horizontal, 16)
                .ledgerSheet()
                .tourAnchor(.purchaseCard)
                fakeRow("Castor oil")
                fakeRow("Sodium hydroxide")
                fakeRow("Lavender essential oil")
                Spacer()
            }
            if wide {
                qualities
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.amber)
                .frame(width: 68, height: 68)
                .tourAnchor(.inventoryAddButton, cornerRadius: 34)
                .padding(20)
        }
        .overlay(alignment: .bottom) {
            Text(verbatim: "Create Batch")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onAmber)
                .padding(.horizontal, 28)
                .frame(height: 60)
                .background(Color.amber, in: Capsule())
                .tourAnchor(.createBatchButton, cornerRadius: 30)
                .padding(.bottom, 20)
        }
        .ledgerBackground()
    }

    private var qualities: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "Qualities").font(.headline)
            ForEach(["Hardness", "Cleansing", "Conditioning", "Lather", "Longevity"], id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: name).font(.subheadline)
                    Capsule().fill(Color.rule).frame(height: 8)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 360, height: 420)
        .ledgerSheet()
        .tourAnchor(.qualityBars)
    }

    private func fakeRow(_ name: String) -> some View {
        HStack {
            Text(verbatim: name)
            Spacer()
            Text(verbatim: "500 g").foregroundStyle(Color.inkSoft)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .ledgerSheet()
    }
}

private extension TourOverlayStep {
    static let previewSearch = TourOverlayStep(
        index: 1,
        count: 10,
        title: "Find what you have",
        body: "Your ingredient library is here. Search it, tap an ingredient to see its purchases, "
            + "and add new ones with the button.",
        targets: [.inventorySearch, .inventoryAddButton]
    )
    static let previewPurchase = TourOverlayStep(
        index: 2,
        count: 10,
        title: "Record what you paid",
        body: "Each purchase keeps its own quantity, price and dates, so costs follow the stock you actually use.",
        targets: [.purchaseCard, .inventoryAddButton]
    )
    static let previewLye = TourOverlayStep(
        index: 4,
        count: 10,
        title: "Set up the lye",
        body: "We’ve filled in a sample recipe. Pick NaOH or KOH, purity, water and superfat, "
            + "and SoapWiz calculates the lye. For a balm or a candle, turn on Non-soap recipe.",
        targets: [.purchaseCard]
    )
    static let previewQualities = TourOverlayStep(
        index: 7,
        count: 10,
        title: "How the bar will turn out",
        body: "See how hard, bubbly and gentle it’ll be. The shaded bands show where a good bar usually sits.",
        targets: [.qualityBars]
    )
    static let previewBatch = TourOverlayStep(
        index: 8,
        count: 10,
        title: "Ready to make it",
        body: "Saved recipes open here with every amount calculated. "
            + "When you’re ready to make soap, tap Create Batch.",
        targets: [.createBatchButton]
    )
}

#Preview("Step 1 light") {
    TourPreviewScreen()
        .tourOverlay(step: .previewSearch, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.light)
}

#Preview("Step 1 dark") {
    TourPreviewScreen()
        .tourOverlay(step: .previewSearch, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.dark)
}

#Preview("Step 2 light") {
    TourPreviewScreen()
        .tourOverlay(step: .previewPurchase, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.light)
}

#Preview("Step 2 dark") {
    TourPreviewScreen()
        .tourOverlay(step: .previewPurchase, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.dark)
}

#Preview("Step 4 light") {
    TourPreviewScreen()
        .tourOverlay(step: .previewLye, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.light)
}

#Preview("Step 8 light") {
    TourPreviewScreen()
        .tourOverlay(step: .previewBatch, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.light)
}

#Preview("Step 8 dark") {
    TourPreviewScreen()
        .tourOverlay(step: .previewBatch, onSkip: {}, onBack: {}, onNext: {})
        .preferredColorScheme(.dark)
}

#Preview("Step 7 iPad light", traits: .fixedLayout(width: 1180, height: 820)) {
    TourPreviewScreen(wide: true)
        .tourOverlay(step: .previewQualities, onSkip: {}, onBack: {}, onNext: {})
        .environment(\.horizontalSizeClass, .regular)
        .preferredColorScheme(.light)
}

#Preview("Step 7 iPad dark", traits: .fixedLayout(width: 1180, height: 820)) {
    TourPreviewScreen(wide: true)
        .tourOverlay(step: .previewQualities, onSkip: {}, onBack: {}, onNext: {})
        .environment(\.horizontalSizeClass, .regular)
        .preferredColorScheme(.dark)
}

#Preview("Step 4 accessibility5") {
    TourPreviewScreen()
        .tourOverlay(step: .previewLye, onSkip: {}, onBack: {}, onNext: {})
        .dynamicTypeSize(.accessibility5)
}
