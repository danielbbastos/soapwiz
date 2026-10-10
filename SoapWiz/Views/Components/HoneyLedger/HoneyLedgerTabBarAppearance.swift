import UIKit

/// The tab bar's inactive tabs in `inkSoft`. SwiftUI's `tint` sets only the
/// selected tab, and iOS 26 ignores `unselectedItemTintColor`, so the rest go
/// through the item appearance. Only the item colours are set: the bar keeps
/// its default backgrounds, and with them the system's glass, and before
/// iOS 26 the transparent bar at the scroll edge.
///
/// Applied once, from the view that builds the tab bar, through `applied`, not
/// at launch: set from the app's `init`, an appearance proxy left the iPad tab
/// bar in the system blue instead of the accent.
enum HoneyLedgerTabBarAppearance {
    static let applied: Void = apply()

    private static func apply() {
        let standard = UITabBarAppearance()
        standard.configureWithDefaultBackground()
        let scrollEdge = UITabBarAppearance()
        scrollEdge.configureWithTransparentBackground()

        let bar = UITabBar.appearance()
        bar.standardAppearance = withInactiveItems(standard)
        bar.scrollEdgeAppearance = withInactiveItems(scrollEdge)
    }

    private static func withInactiveItems(_ appearance: UITabBarAppearance) -> UITabBarAppearance {
        let inactive = UIColor(named: "InkSoft") ?? .secondaryLabel
        let items = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for item in items {
            item.normal.iconColor = inactive
            item.normal.titleTextAttributes = [.foregroundColor: inactive]
        }
        return appearance
    }
}
