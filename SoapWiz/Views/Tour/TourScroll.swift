import SwiftUI

/// Where the tour scrolls a form to, so the card a step points at is in view
/// rather than running under the tab bar or past the bottom of a sheet.
enum TourScrollTarget: Hashable {
    /// The recipe form's Config tab, for the basics step.
    case oilsCard
    /// The Create Batch sheet's Cure section, for the batch step.
    case cureSection

    var phase: TourPhase {
        switch self {
        case .oilsCard: .step(.basics)
        case .cureSection: .step(.batch)
        }
    }

    /// An iPad's recipe form already has the Oils card in view; the Cure
    /// section can be pushed out of the sheet on either, by large text.
    var isPhoneOnly: Bool {
        switch self {
        case .oilsCard: true
        case .cureSection: false
        }
    }

    /// Where in the scroll view the target is put: just under the pinned tab
    /// picker for the Oils card, with room above it for its header.
    var anchor: UnitPoint {
        switch self {
        case .oilsCard: UnitPoint(x: 0.5, y: 0.08)
        case .cureSection: .top
        }
    }

    /// Long enough for the rows to be laid out, so the scroll lands. The step
    /// on a sheet gets less: the guide's wait for its targets began when the
    /// sheet was asked for, so part of it is gone by the time the form appears.
    var layoutDelay: Duration {
        switch self {
        case .oilsCard: .milliseconds(250)
        case .cureSection: .milliseconds(100)
        }
    }

    func applies(to phase: TourPhase, isPad: Bool) -> Bool {
        phase == self.phase && !(isPhoneOnly && isPad)
    }
}

extension View {
    /// Scrolls a form to `target` once the tour reaches the step that points at
    /// it. The view with the matching `.id` must exist in the form even when
    /// its rows are not laid out. Does nothing outside the tour.
    func scrollsForTour(to target: TourScrollTarget) -> some View {
        modifier(TourScroll(target: target))
    }
}

private struct TourScroll: ViewModifier {
    let target: TourScrollTarget

    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: guide?.phase) {
                    guard let guide, target.applies(to: guide.phase, isPad: guide.isPad) else { return }
                    try? await Task.sleep(for: target.layoutDelay)
                    guard !Task.isCancelled else { return }
                    withAnimation { proxy.scrollTo(target, anchor: target.anchor) }
                }
        }
    }
}
