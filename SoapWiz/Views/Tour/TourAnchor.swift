import SwiftUI

/// The controls the onboarding tour can point at.
enum TourAnchorID: Hashable {
    case inventorySearch
    case inventoryAddButton
    case purchaseCard
    case addPurchaseButton
    case recipeRow
    case recipeAddButton
    case formTabs
    case configOilsCard
    case oilsCard
    case costPanel
    case qualityBars
    case createBatchButton
    case cureCard
    case batchRow
}

/// Where a tagged control is, and the corner radius its spotlight should have.
/// A target tagged in more than one place, such as the first and last rows of a
/// section, is lit as the rectangle that holds them all, grown by `outset`.
struct TourAnchorTarget {
    let bounds: [Anchor<CGRect>]
    let cornerRadius: CGFloat
    let outset: CGSize
}

struct TourAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TourAnchorID: TourAnchorTarget] = [:]

    static func reduce(value: inout [TourAnchorID: TourAnchorTarget], nextValue: () -> [TourAnchorID: TourAnchorTarget]) {
        value.merge(nextValue()) { current, new in
            TourAnchorTarget(
                bounds: current.bounds + new.bounds,
                cornerRadius: current.cornerRadius,
                outset: current.outset
            )
        }
    }
}

/// Which anchors are on screen, apart from where. `Anchor` is not `Equatable`,
/// so the overlay's own preference can't tell a host when the set changes;
/// this one can.
struct TourAnchorIDsPreferenceKey: PreferenceKey {
    static let defaultValue: Set<TourAnchorID> = []

    static func reduce(value: inout Set<TourAnchorID>, nextValue: () -> Set<TourAnchorID>) {
        value.formUnion(nextValue())
    }
}

extension View {
    /// Tags a ledger card or row so the spotlight sits just outside the card's
    /// own edge, with its background, corners and edge lit inside the ring.
    ///
    /// A list row's content is inset from its background (15 pt sideways and
    /// about 13 pt up and down), so the outset is that inset plus a 6 pt gap,
    /// and the radius is the card's 26 pt plus the gap, which keeps the curves
    /// parallel. Tag the first and last rows of a section with it to light the
    /// whole card.
    func tourCardAnchor(_ id: TourAnchorID?) -> some View {
        tourAnchor(id, cornerRadius: 32, outset: CGSize(width: 21, height: 19))
    }

    /// Marks this view as a place the tour can spotlight. Costs nothing when
    /// no `tourOverlay` is reading the anchors. A nil `id` tags nothing, for
    /// a control shared with screens that have no step of their own.
    ///
    /// Tagging several views with one `id` lights the rectangle around all of
    /// them, with the first's corner radius and outset.
    ///
    /// `outset` grows the lit area past the view: a list row's content sits
    /// inside the padding of its background, so the spotlight needs it to
    /// match the row, and a button that is the same colour as the ring needs
    /// room for the ring to show.
    func tourAnchor(_ id: TourAnchorID?, cornerRadius: CGFloat = 22, outset: CGSize = .zero) -> some View {
        anchorPreference(key: TourAnchorPreferenceKey.self, value: .bounds) { bounds in
            guard let id else { return [:] }
            return [id: TourAnchorTarget(bounds: [bounds], cornerRadius: cornerRadius, outset: outset)]
        }
        .preference(key: TourAnchorIDsPreferenceKey.self, value: id.map { [$0] } ?? [])
    }
}
