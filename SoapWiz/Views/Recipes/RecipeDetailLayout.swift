import SwiftUI

/// Which layout the recipe detail gets for a given size class and measured
/// detail-column width. Width matters because the size class alone can't tell
/// a full-width detail column from one squeezed by the sidebar.
enum RecipeDetailLayout: Equatable {
    /// One column of stacked sections (compact, or regular squeezed by the sidebar in portrait).
    case stacked
    /// Ingredients beside calculated amounts; chart and cost span full width below.
    case sideBySideTop
    /// `sideBySideTop` plus the soap-properties chart paired with the cost
    /// breakdown (landscape with the sidebar collapsed).
    case wide

    init(sizeClass: UserInterfaceSizeClass?, width: Double) {
        guard sizeClass == .regular else {
            self = .stacked
            return
        }
        switch width {
        case ..<700: self = .stacked
        case ..<1000: self = .sideBySideTop
        default: self = .wide
        }
    }
}
