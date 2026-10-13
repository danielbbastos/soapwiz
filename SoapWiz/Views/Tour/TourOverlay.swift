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
            }
        }
    }

    private func cutouts(for step: TourOverlayStep, in proxy: GeometryProxy) -> [TourCutout] {
        let resolved = step.targets.compactMap { id -> TourCutout? in
            guard let target = anchors[id] else { return nil }
            return TourCutout(rect: proxy[target.bounds], cornerRadius: target.cornerRadius)
        }
        return Array(resolved.prefix(2))
    }

    /// `safeInsets` come from outside the `ignoresSafeArea` that lets the dim
    /// reach the screen's edges, since inside it the proxy reports none.
    private func content(for step: TourOverlayStep, in proxy: GeometryProxy, safeInsets: TourSafeInsets) -> some View {
        let cutouts = cutouts(for: step, in: proxy)
        let placement = cardSize.map { size in
            TourCardPlacement.place(
                container: proxy.size,
                safeInsets: safeInsets,
                cutouts: cutouts.map(\.rect),
                cardSize: size,
                allowsSide: horizontalSizeClass == .regular
            )
        }
        let origin = placement?.origin ?? .zero
        let width = TourCardPlacement.cardWidth(for: proxy.size.width)
        let animation: Animation? = reduceMotion ? nil : .smooth

        return ZStack(alignment: .topLeading) {
            dim(cutouts: cutouts)
            ForEach(Array(cutouts.enumerated()), id: \.offset) { _, cutout in
                ring(for: cutout)
            }
            card(for: step, width: width, placement: placement, hasCutouts: !cutouts.isEmpty)
                .offset(x: origin.x, y: origin.y)
                .opacity(placement == nil ? 0 : 1)
            measuringCard(for: step, width: width)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .animation(animation, value: placement)
        .animation(animation, value: cutouts)
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
            edge: hasCutouts ? placement?.edge : nil,
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

    private func dim(cutouts: [TourCutout]) -> some View {
        let first = cutouts.first ?? TourCutout(rect: .zero, cornerRadius: 0)
        let second = cutouts.count > 1 ? cutouts[1] : TourCutout(rect: first.rect.centrePoint, cornerRadius: 0)
        return ZStack {
            TourDimShape(first: first, second: second)
                .fill(Color.tourDim, style: FillStyle(eoFill: true))
            if reduceTransparency {
                TourDimShape(first: first, second: second)
                    .fill(Color.tourDim.opacity(0.7), style: FillStyle(eoFill: true))
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

private extension CGRect {
    /// A zero-size rect at this one's centre, for a hole that isn't there yet.
    var centrePoint: CGRect {
        CGRect(x: midX, y: midY, width: 0, height: 0)
    }
}

/// A spotlight's rounded rectangle, animatable so a step change glides.
private struct TourCutout: Equatable, Animatable {
    var rect: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(rect.animatableData, cornerRadius) }
        set {
            rect.animatableData = newValue.first
            cornerRadius = newValue.second
        }
    }
}

/// The whole container with a hole per cutout, for an even-odd fill.
private struct TourDimShape: Shape {
    var first: TourCutout
    var second: TourCutout

    var animatableData: AnimatablePair<TourCutout.AnimatableData, TourCutout.AnimatableData> {
        get { AnimatablePair(first.animatableData, second.animatableData) }
        set {
            first.animatableData = newValue.first
            second.animatableData = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for cutout in [first, second] where cutout.rect.width > 0 && cutout.rect.height > 0 {
            path.addPath(RoundedRectangle(cornerRadius: cutout.cornerRadius, style: .continuous).path(in: cutout.rect))
        }
        return path
    }
}

/// The cutout's outline pushed out by `outset`, so a stroke centred on it
/// sits wholly outside the lit area.
private struct TourRingShape: Shape {
    var cutout: TourCutout
    let outset: CGFloat

    var animatableData: TourCutout.AnimatableData {
        get { cutout.animatableData }
        set { cutout.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cutout.cornerRadius + outset, style: .continuous)
            .path(in: cutout.rect.insetBy(dx: -outset, dy: -outset))
    }
}
