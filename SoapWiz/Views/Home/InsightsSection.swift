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
            .frame(maxWidth: isWide ? HomeLayout.maximumWidth : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private var cards: some View {
        InsightsColumnsLayout(isWide: isWide) {
            BatchHeatmapCard(isWide: isWide)
            CostPerWeightCard()
        }
    }
}

/// Lays out Insights' cards in one layout for both shapes, so they keep their
/// identity when the window rotates. Wide, on Home's three-column grid, the
/// first card spans two columns and a second, when there is one, takes the
/// third; narrow, they stack.
struct InsightsColumnsLayout: Layout {
    let isWide: Bool

    static func widths(count: Int, width: CGFloat, isWide: Bool) -> [CGFloat] {
        guard isWide else { return Array(repeating: width, count: count) }
        let columns = CGFloat(HomeLayout.wideColumnCount)
        let column = (width - HomeLayout.spacing * (columns - 1)) / columns
        return (0..<count).map { $0 == 0 ? column * 2 + HomeLayout.spacing : column }
    }

    /// Each card's frame from its height, with the layout's origin at zero.
    static func frames(heights: [CGFloat], width: CGFloat, isWide: Bool) -> [CGRect] {
        let widths = widths(count: heights.count, width: width, isWide: isWide)
        var frames: [CGRect] = []
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        for (height, cardWidth) in zip(heights, widths) {
            frames.append(CGRect(x: originX, y: originY, width: cardWidth, height: height))
            if isWide {
                originX += cardWidth + HomeLayout.spacing
            } else {
                originY += height + HomeLayout.spacing
            }
        }
        return frames
    }

    private func measuredFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let widths = Self.widths(count: subviews.count, width: width, isWide: isWide)
        let heights = zip(subviews, widths).map { subview, cardWidth in
            subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
        }
        return Self.frames(heights: heights, width: width, isWide: isWide)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let frames = measuredFrames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = measuredFrames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
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
