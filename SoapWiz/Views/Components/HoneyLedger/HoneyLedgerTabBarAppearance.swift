import UIKit

/// The tab bar's inactive tabs in `inkSoft`. SwiftUI's `tint` sets only the
/// selected tab, and iOS 26 ignores `unselectedItemTintColor`, so the rest go
/// through the item appearance. Only the item colours are set: the bar keeps
/// its default background, and with it the system's glass.
///
/// Applied once, from the view that builds the tab bar, through `applied`, not
/// at launch: set from the app's `init`, an appearance proxy left the iPad tab
/// bar in the system blue instead of the accent.
enum HoneyLedgerTabBarAppearance {
    static let applied: Void = apply()

    private static func apply() {
        let inactive = UIColor(named: "InkSoft") ?? .secondaryLabel
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = inactive
            item.normal.titleTextAttributes = [.foregroundColor: inactive]
        }
        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }
}
