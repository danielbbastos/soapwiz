import SwiftUI

/// Where the tour scrolls the recipe form's Config tab to.
enum TourConfigScrollTarget: Hashable {
    case oilsCard
}

extension View {
    /// Scrolls the Config tab for the tour's basics step, so the whole Oils card
    /// and its header are in view rather than running under the tab bar on an
    /// iPhone. An iPad's form already has the card in view. Does nothing
    /// outside the tour.
    func scrollsForTour() -> some View {
        modifier(TourConfigScroll())
    }
}

private struct TourConfigScroll: ViewModifier {
    /// Long enough for the rows to be laid out, so the scroll lands.
    private static let layoutDelay: Duration = .milliseconds(250)

    /// Just under the pinned tab picker, with room above the card for its header.
    private static let anchor = UnitPoint(x: 0.5, y: 0.08)

    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: guide?.phase) {
                    guard let guide, !guide.isPad, guide.phase == .step(.basics) else { return }
                    try? await Task.sleep(for: Self.layoutDelay)
                    guard !Task.isCancelled else { return }
                    withAnimation { proxy.scrollTo(TourConfigScrollTarget.oilsCard, anchor: Self.anchor) }
                }
        }
    }
}
