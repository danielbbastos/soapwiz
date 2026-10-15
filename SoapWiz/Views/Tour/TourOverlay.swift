import SwiftUI

/// One step of the tour as the overlay draws it. `index` counts from 1.
struct TourOverlayStep: Equatable {
    let index: Int
    let count: Int
    let title: String
    let body: String
    let targets: [TourAnchorID]
}

extension View {
    /// Dims everything this view draws, cuts a lit hole around each of the
    /// step's targets, and sets a caption card beside them. A nil step draws
    /// nothing. A target nobody tagged with `tourAnchor` is left out.
    func tourOverlay(
        step: TourOverlayStep?,
        onSkip: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
            TourOverlayLayer(step: step, anchors: anchors, onSkip: onSkip, onBack: onBack, onNext: onNext)
        }
    }
}

extension TourSafeInsets {
    init(_ insets: EdgeInsets) {
        self.init(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }
}

/// How a step change plays. Nothing slides: the spotlight and card that are
/// leaving fade out where they are, the new spotlight fades in on its target
/// wherever that is as it arrives, and the card fades in once the target has
/// stopped moving.
enum TourMotion {
    /// The cost panel's own length and curve, which the tour opens and closes
    /// it with.
    static let duration: TimeInterval = 0.25

    static var animation: Animation { .easeInOut(duration: duration) }

    static let fadeOut: TimeInterval = 0.12
    static let spotlightFadeIn: TimeInterval = 0.15
    static let cardFadeIn: TimeInterval = 0.15

    /// How long a target must have kept still before the card is placed by it.
    /// Long enough to span the gaps between a screen being pushed and the form
    /// then scrolling, which a shorter wait takes for the target having stopped.
    static let quietPeriod: TimeInterval = 0.3

    /// The longest the card waits for a target that never stops, or never comes.
    static let longestWait: TimeInterval = 1.5
}

private struct TourOverlayLayer: View {
    let step: TourOverlayStep?
    let anchors: [TourAnchorID: TourAnchorTarget]
    let onSkip: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cardSize: CGSize?

    /// The step the three below belong to: what the overlay last settled on,
    /// which lags `step` for the one pass between a step change and it being
    /// noticed. What leaves is drawn from these.
    @State private var shown: TourOverlayStep?
    @State private var shownCutouts: [TourCutout] = []
    @State private var shownPlacement: TourCardPlacement.Result?

    /// When the targets or the card's placement last changed.
    @State private var lastMoved = Date.distantPast

    /// The step change under way, until its card has faded in.
    @State private var change: TourChange?

    var body: some View {
        Group {
            if let step {
                GeometryReader { safeProxy in
                    GeometryReader { proxy in
                        content(for: step, in: proxy, safeInsets: TourSafeInsets(safeProxy.safeAreaInsets))
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .onChange(of: step?.index) { _, newIndex in
            if newIndex != nil {
                AccessibilityNotification.ScreenChanged(nil).post()
            } else {
                // Another layer has the step now.
                shown = nil
                change = nil
            }
        }
        .task(id: change?.start) {
            guard let change else { return }
            while !Task.isCancelled, Date.now < settledAt(change).addingTimeInterval(TourMotion.cardFadeIn) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            self.change = nil
        }
    }

    private func cutouts(for step: TourOverlayStep, in proxy: GeometryProxy) -> [TourCutout] {
        let resolved = step.targets.compactMap { id -> TourCutout? in
            guard let target = anchors[id], let first = target.bounds.first else { return nil }
            let rect = target.bounds.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
            let grown = rect.insetBy(dx: -target.outset.width, dy: -target.outset.height)
            return TourCutout(rect: grown, cornerRadius: target.cornerRadius)
        }
        return Array(resolved.prefix(2))
    }

    /// When the new card may start to fade in: once the targets have kept
    /// still for a moment, and the old card has gone. Never while there are no
    /// targets, which the card would be placed by the middle of the screen for.
    private func settledAt(_ change: TourChange) -> Date {
        let fadedOut = change.start.addingTimeInterval(change.leaving == nil ? 0 : TourMotion.fadeOut)
        let still = shownCutouts.isEmpty ? .distantFuture : lastMoved.addingTimeInterval(TourMotion.quietPeriod)
        return min(max(still, fadedOut), change.start.addingTimeInterval(TourMotion.longestWait))
    }

    /// What is drawn at `date`. The spotlights follow their targets exactly,
    /// with no animation of their own, since a target can itself be moving (the
    /// cost bar opening into its panel, a screen being pushed) and anything
    /// laid over that would trail it.
    private func frame(
        for step: TourOverlayStep,
        targets: [TourCutout],
        placement: TourCardPlacement.Result?,
        at date: Date,
        isPending: Bool
    ) -> TourFrame {
        if shown == nil, change == nil {
            // Before the overlay has noticed it is up: nothing drawn yet.
            return TourFrame(cutouts: targets, hole: 1, ring: 0, cardStep: step, placement: placement, cardOpacity: 0)
        }
        let start: Date
        let leaving: TourLeaving?
        if isPending, let shown {
            // The pass between the step changing and the change being noticed:
            // still the old card and spotlight, so nothing flashes.
            start = date
            leaving = TourLeaving(step: shown, cutouts: shownCutouts, placement: shownPlacement)
        } else if let change {
            start = change.start
            leaving = change.leaving
        } else {
            return TourFrame(cutouts: targets, hole: 0, ring: 1, cardStep: step, placement: placement, cardOpacity: 1)
        }
        let elapsed = date.timeIntervalSince(start)
        if let leaving, elapsed < TourMotion.fadeOut {
            let progress = elapsed / TourMotion.fadeOut
            return TourFrame(
                cutouts: leaving.cutouts,
                hole: progress,
                ring: 1 - progress,
                cardStep: leaving.step,
                placement: leaving.placement,
                cardOpacity: 1 - progress
            )
        }
        let arriving = elapsed - (leaving == nil ? 0 : TourMotion.fadeOut)
        let spotlight = min(1, max(0, arriving / TourMotion.spotlightFadeIn))
        let card = min(1, max(0, date.timeIntervalSince(settledAt(TourChange(start: start, leaving: leaving)))
            / TourMotion.cardFadeIn))
        return TourFrame(
            cutouts: targets,
            hole: 1 - spotlight,
            ring: spotlight,
            cardStep: step,
            placement: placement,
            cardOpacity: card
        )
    }

    private func noticeChange(
        from old: TourSpotlightKey,
        to new: TourSpotlightKey,
        step: TourOverlayStep
    ) {
        let isFirst = shown == nil
        let startsChange = isFirst || old.index != new.index
        var leaving: TourLeaving?
        if !isFirst, old.index != new.index, let shown {
            leaving = TourLeaving(step: shown, cutouts: old.cutouts, placement: old.placement)
        }
        shown = step
        shownCutouts = new.cutouts
        shownPlacement = new.placement
        lastMoved = .now
        if startsChange, !reduceMotion {
            change = TourChange(start: .now, leaving: leaving)
        }
    }

    /// `safeInsets` come from outside the `ignoresSafeArea` that lets the dim
    /// reach the screen's edges, since inside it the proxy reports none.
    private func content(for step: TourOverlayStep, in proxy: GeometryProxy, safeInsets: TourSafeInsets) -> some View {
        let targets = cutouts(for: step, in: proxy)
        let placement = cardSize.map { size in
            TourCardPlacement.place(
                container: proxy.size,
                safeInsets: safeInsets,
                cutouts: targets.map(\.rect),
                cardSize: size,
                allowsSide: horizontalSizeClass == .regular
            )
        }
        let width = TourCardPlacement.cardWidth(for: proxy.size.width)
        let key = TourSpotlightKey(index: step.index, cutouts: targets, placement: placement)
        let isPending = shown != nil && shown?.index != step.index

        return TimelineView(.animation(paused: change == nil && !isPending)) { timeline in
            let frame = frame(for: step, targets: targets, placement: placement, at: timeline.date, isPending: isPending)
            let origin = frame.placement?.origin ?? .zero
            ZStack(alignment: .topLeading) {
                dim(cutouts: frame.cutouts, hole: frame.hole)
                ForEach(Array(frame.cutouts.enumerated()), id: \.offset) { _, cutout in
                    ring(for: cutout)
                        .opacity(frame.ring)
                }
                card(for: frame.cardStep, width: width, placement: frame.placement, hasCutouts: !frame.cutouts.isEmpty)
                    .offset(x: origin.x, y: origin.y)
                    .opacity(frame.placement == nil ? 0 : frame.cardOpacity)
                measuringCard(for: step, width: width)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        // Everything here is moved by the clock. The animation the cost panel
        // opens with is in the transaction too, since its anchor drives this
        // view, and would slide the card and fade it on its own curve.
        .transaction { $0.animation = nil }
        .onChange(of: key, initial: true) { old, new in
            noticeChange(from: old, to: new, step: step)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func card(
        for step: TourOverlayStep,
        width: CGFloat,
        placement: TourCardPlacement.Result?,
        hasCutouts: Bool
    ) -> some View {
        TourCaptionCard(
            step: step,
            width: width,
            edge: hasCutouts && placement?.showsNotch == true ? placement?.edge : nil,
            notchOffset: placement?.notchOffset ?? 0,
            maxHeight: placement?.maxHeight,
            onSkip: onSkip,
            onBack: onBack,
            onNext: onNext
        )
    }

    /// An unseen copy at the card's natural height, so placement knows how
    /// tall the card wants to be even while the visible one is held shorter.
    private func measuringCard(for step: TourOverlayStep, width: CGFloat) -> some View {
        TourCaptionCard(
            step: step,
            width: width,
            edge: nil,
            notchOffset: 0,
            maxHeight: nil,
            onSkip: {},
            onBack: {},
            onNext: {}
        )
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
    }

    /// The dim with a hole per cutout. A hole is closed again, to the degree
    /// `hole` says, by laying the dim over it, which is how a spotlight fades.
    private func dim(cutouts: [TourCutout], hole: Double) -> some View {
        let first = cutouts.first ?? TourCutout(rect: .zero, cornerRadius: 0)
        let second = cutouts.count > 1 ? cutouts[1] : TourCutout(rect: first.rect.centrePoint, cornerRadius: 0)
        return ZStack {
            TourDimShape(first: first, second: second)
                .fill(Color.tourDim, style: FillStyle(eoFill: true))
            if reduceTransparency {
                TourDimShape(first: first, second: second)
                    .fill(Color.tourDim.opacity(0.7), style: FillStyle(eoFill: true))
            }
            if hole > 0 {
                TourHoleShape(first: first, second: second)
                    .fill(Color.tourDim)
                    .opacity(hole)
                if reduceTransparency {
                    TourHoleShape(first: first, second: second)
                        .fill(Color.tourDim.opacity(0.7))
                        .opacity(hole)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    private func ring(for cutout: TourCutout) -> some View {
        ZStack {
            if !reduceTransparency {
                TourRingShape(cutout: cutout, outset: 4)
                    .stroke(Color.amberBright.opacity(0.25), lineWidth: 8)
            }
            TourRingShape(cutout: cutout, outset: 1)
                .stroke(Color.amberBright, lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
