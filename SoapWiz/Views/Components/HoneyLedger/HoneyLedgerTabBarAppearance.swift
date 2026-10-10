import UIKit

/// The tab bar's inactive tabs in `inkSoft`. SwiftUI's `tint` sets only the
/// selected tab, and iOS 26 ignores `unselectedItemTintColor`, so the rest go
/// through the item appearance. On iOS 26 only the item colours are set: the
/// bar keeps its default backgrounds, and with them the system's glass. Before
/// iOS 26 the system's bar is a whitish material that changes to transparent at
/// the scroll edge, so it differs between tabs; there both appearances are one
/// opaque `paper` bar with a `rule` hairline on top.
///
/// Applied once, from the view that builds the tab bar, through `applied`, not
/// at launch: set from the app's `init`, an appearance proxy left the iPad tab
/// bar in the system blue instead of the accent.
enum HoneyLedgerTabBarAppearance {
    static let applied: Void = apply()

    private static func apply() {
        let standard = UITabBarAppearance()
        let scrollEdge = UITabBarAppearance()
        if #available(iOS 26, *) {
            standard.configureWithDefaultBackground()
            scrollEdge.configureWithTransparentBackground()
        } else {
            for appearance in [standard, scrollEdge] {
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(named: "Paper")
                appearance.shadowColor = UIColor(named: "Rule")
            }
        }

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
