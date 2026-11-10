import SwiftData
import SwiftUI

/// Home's Insights: a section label over the Insights cards. Absent until a
/// batch has been made; Pro sees the cards, the free tier a locked preview.
struct InsightsSection: View {
    @Environment(BatchRows.self) private var batchRows
    @FreeTierGateEnvironment private var freeTier

    let isWide: Bool

    var body: some View {
        if !batchRows.batches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HoneyLedgerSectionLabel("Insights")
                if freeTier.gate.allows(.insights) {
                    cards
                } else {
                    InsightsLockedPreview {
                        freeTier.presentUpgrade(for: .insights)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if isWide {
            InsightsWideRow {
                BatchHeatmapCard(isWide: true)
                CostPerWeightCard()
            }
        } else {
            VStack(spacing: HomeLayout.spacing) {
                BatchHeatmapCard(isWide: false)
                CostPerWeightCard()
            }
        }
    }
}

/// Lays out a wide row on Home's three-column grid: the first card spans two
/// columns, and a second, when there is one, takes the third.
private struct InsightsWideRow: Layout {
    private let columnCount: CGFloat = CGFloat(HomeLayout.wideColumnCount)

    private func columnWidth(_ proposal: ProposedViewSize) -> CGFloat {
        let total = proposal.width ?? 600
        return (total - HomeLayout.spacing * (columnCount - 1)) / columnCount
    }

    private func width(of index: Int, _ proposal: ProposedViewSize) -> CGFloat {
        let column = columnWidth(proposal)
        return index == 0 ? column * 2 + HomeLayout.spacing : column
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(ProposedViewSize(width: width(of: index, proposal), height: nil)).height
        }.max() ?? 0
        return CGSize(width: proposal.width ?? 600, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var originX = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let cardWidth = width(of: index, ProposedViewSize(width: bounds.width, height: nil))
            subview.place(
                at: CGPoint(x: originX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cardWidth, height: nil)
            )
            originX += cardWidth + HomeLayout.spacing
        }
    }
}

/// What the free tier sees instead of the cards: a blurred sketch of them
/// under the pitch and the way to upgrade.
private struct InsightsLockedPreview: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("See how your soap adds up")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("Your batch rhythm over the year, and cost per kg by recipe.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
            Button("Unlock with SoapWiz Pro", action: onUnlock)
                .buttonStyle(.honeyLedgerPrimaryCompact)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background {
            InsightsSketch()
                .blur(radius: 5)
                .opacity(0.55)
                .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .ledgerSheet()
    }
}

/// Static stand-in shapes for a heatmap and three bars.
private struct InsightsSketch: View {
    private let barFractions: [CGFloat] = [0.85, 0.6, 0.4]

    var body: some View {
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<4, id: \.self) { row in
                    GridRow {
                        ForEach(0..<13, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.heatmapLevel((row * 5 + column * 3) % 4))
                                .frame(height: 18)
                        }
                    }
                }
            }
            ForEach(barFractions, id: \.self) { fraction in
                Spacer(minLength: 12)
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.heatmapLevel(2))
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Insights, Pro") {
    let data = BatchHeatmapPreviewData()
    InsightsSection(isWide: false)
        .padding(16)
        .ledgerBackground()
        .environment(\.isTourSandbox, true)
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}

#Preview("Insights, free") {
    let data = BatchHeatmapPreviewData()
    InsightsSection(isWide: false)
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}

#Preview("Insights, iPad", traits: .fixedLayout(width: 1_000, height: 420)) {
    let data = BatchHeatmapPreviewData()
    InsightsSection(isWide: true)
        .padding(16)
        .ledgerBackground()
        .environment(\.isTourSandbox, true)
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}
#endif
