import SwiftUI

enum RecipeTab: String {
    case config = "Config"
    case ingredients = "Ingredients"
    case stats = "Stats"
    case ingredientsAndStats = "Ingredients & Stats"

    static func tabs(isWide: Bool) -> [RecipeTab] {
        isWide ? [.config, .ingredientsAndStats] : [.config, .ingredients, .stats]
    }

    /// The tab that stands in for this one when the layout changes, so a form
    /// that is rotated or resized keeps the user on the content they were
    /// looking at instead of on a tab the picker no longer offers.
    func adapted(isWide: Bool) -> RecipeTab {
        switch self {
        case .config:
            return .config
        case .ingredients, .stats:
            return isWide ? .ingredientsAndStats : self
        case .ingredientsAndStats:
            return isWide ? self : .ingredients
        }
    }
}

/// Decided by the form's own measured width, not the size class: an iPad Air
/// 11" is narrow in portrait (820 pt) and wide in landscape (1,180 pt), and a
/// narrow Split View or Stage Manager window falls back on its own. Matches
/// `ListDetailLayout.minimumWideWidth` in spirit, but is the form's own
/// threshold and may move independently.
enum RecipeFormLayout {
    /// Puts the iPad Air 11" in landscape (1,180 pt) and the 13" in portrait
    /// (1,032 pt) on the wide side, and the 11" in portrait (820 pt) off it.
    static let minimumWideWidth: CGFloat = 1_000

    static let statsColumnWidth: CGFloat = 400

    static let columnSpacing: CGFloat = 20

    /// The two columns stop here and stay centred, so Ingredients never grows
    /// past its readable width however wide the window gets.
    static let maximumWideWidth = ReadableWidth.maximum + columnSpacing + statsColumnWidth

    static func isWide(width: CGFloat) -> Bool {
        width >= minimumWideWidth
    }
}
