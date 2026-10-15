import SwiftUI

extension View {
    /// Draws the tour's overlay over this view when the step on show belongs
    /// to `layer`, and tells the guide which tagged controls this view has.
    /// Does nothing outside the tour.
    ///
    /// One per presentation: a cover or a sheet is a hierarchy of its own, so
    /// the overlay on the tabs can neither dim it nor see its controls.
    func tourOverlayHost(_ layer: TourLayer) -> some View {
        modifier(TourOverlayHost(layer: layer))
    }
}

private struct TourOverlayHost: ViewModifier {
    let layer: TourLayer

    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        if let guide {
            content.modifier(TourGuidedLayer(guide: guide, layer: layer))
        } else {
            content
        }
    }
}

private struct TourGuidedLayer: ViewModifier {
    let guide: TourGuide
    let layer: TourLayer

    func body(content: Content) -> some View {
        content
            .tourOverlay(
                step: guide.overlayStep(for: layer),
                onSkip: guide.skip,
                onBack: guide.back,
                onNext: guide.next
            )
            .overlay {
                // The welcome and closing cards have no cutouts, so only the
                // tabs, which are always there, draw them.
                if layer == .tabs, let kind = guide.fullCardKind {
                    TourFullCard(kind: kind, onPrimary: guide.primaryAction, onSkip: guide.skip)
                } else if guide.dims(layer) {
                    // Another layer has the step. The tabs sit beneath a sheet
                    // or cover that has it, so this shows only where that
                    // doesn't reach; a sheet or cover shows it while it closes.
                    Color.tourDim
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                }
            }
            .onPreferenceChange(TourAnchorIDsPreferenceKey.self) { guide.report($0, in: layer) }
            // A cover or sheet that goes takes its controls with it without
            // the preference changing.
            .onDisappear { guide.report([], in: layer) }
    }
}
