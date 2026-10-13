import SwiftUI

/// The controls the onboarding tour can point at.
enum TourAnchorID: Hashable {
    case inventorySearch
    case addButton
    case purchaseCard
    case recipeRow
    case recipeConfig
    case oilsCard
    case costPanel
    case qualityBars
    case createBatchButton
    case cureCard
    case batchRow
}

/// Where a tagged control is, and the corner radius its spotlight should have.
struct TourAnchorTarget {
    let bounds: Anchor<CGRect>
    let cornerRadius: CGFloat
}

struct TourAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TourAnchorID: TourAnchorTarget] = [:]

    static func reduce(value: inout [TourAnchorID: TourAnchorTarget], nextValue: () -> [TourAnchorID: TourAnchorTarget]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as a place the tour can spotlight. Costs nothing when
    /// no `tourOverlay` is reading the anchors.
    func tourAnchor(_ id: TourAnchorID, cornerRadius: CGFloat = 22) -> some View {
        anchorPreference(key: TourAnchorPreferenceKey.self, value: .bounds) { bounds in
            [id: TourAnchorTarget(bounds: bounds, cornerRadius: cornerRadius)]
        }
    }
}
