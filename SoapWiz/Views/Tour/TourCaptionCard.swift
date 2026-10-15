import SwiftUI

/// The step's text, progress and buttons on a raised card, with a notch
/// pointing at the spotlight on the edge `edge` names. A nil `edge` draws no
/// notch. With a `maxHeight`, the card is exactly that tall: the header, text
/// and Back scroll, and only a slim Skip and Next row stays pinned.
struct TourCaptionCard: View {
    let step: TourOverlayStep
    let width: CGFloat
    let edge: TourCardEdge?
    let notchOffset: CGFloat
    let maxHeight: CGFloat?
    let onSkip: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        Group {
            if maxHeight != nil {
                clampedContent
            } else {
                content
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(width: width, height: maxHeight, alignment: .topLeading)
        .background {
            ZStack {
                if let edge {
                    notch(on: edge)
                }
                TourCardSurface(cornerRadius: 18)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            text
            buttons
                .padding(.top, 14)
        }
    }

    /// For a card held shorter than it wants to be: everything scrolls but a
    /// slim Skip and Next row, and Back, which would not fit beside them,
    /// moves to the end of the scrolling text. The scroll area takes whatever
    /// the pinned row leaves, which can be little, but the card itself never
    /// grows past its `maxHeight`.
    private var clampedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    text
                    backButton
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                skipButton
                Spacer(minLength: 0)
                nextButton
            }
            .padding(.top, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("STEP \(step.index) OF \(step.count)")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Step \(step.index) of \(step.count)")
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(0..<max(step.count, 0), id: \.self) { position in
                    Capsule()
                        .fill(position < step.index ? Color.amber : Color.rule)
                        .frame(height: 4)
                }
            }
            .frame(width: 130)
            .accessibilityHidden(true)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(step.body)
                .font(.callout)
                .foregroundStyle(Color.inkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                skipButton
                Spacer(minLength: 0)
                backButton
                nextButton
            }
            VStack(alignment: .trailing, spacing: 8) {
                nextButton
                backButton
                skipButton
            }
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip tour")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(Color.inkSoft)
        .frame(minHeight: 44)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Text("Back")
                .font(.body)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 18)
                .frame(maxWidth: maxHeight == nil ? nil : .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color.ruleStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button(action: onNext) {
            Text("Next")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(.honeyLedgerPrimaryCompact)
    }

    @ViewBuilder
    private func notch(on edge: TourCardEdge) -> some View {
        let square = RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.paperRaised)
            .frame(width: TourCardPlacement.notchSize, height: TourCardPlacement.notchSize)
            .rotationEffect(.degrees(45))
        let half = TourCardPlacement.notchSize / 2
        switch edge {
        case .below:
            square
                .offset(x: notchOffset, y: -half)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .above:
            square
                .offset(x: notchOffset, y: half)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        case .leading:
            square
                .offset(x: half, y: notchOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        case .trailing:
            square
                .offset(x: -half, y: notchOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
