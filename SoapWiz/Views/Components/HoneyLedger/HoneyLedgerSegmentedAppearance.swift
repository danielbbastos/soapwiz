import UIKit

/// The system segmented control in Honey Ledger colours: the selected segment
/// `paperRaised` with its label `ink` semibold, the others `inkSoft`. SwiftUI's
/// `tint` doesn't reach a segmented picker, so this goes through UIKit's
/// appearance proxy, which applies app-wide; the track is drawn by each call
/// site.
///
/// Applied once, from the first view that builds a segmented picker, through
/// `applied`, not at launch: set from the app's `init`, the proxy left the
/// iPad tab bar in the system blue instead of the accent.
enum HoneyLedgerSegmentedAppearance {
    static let applied: Void = apply()

    private static func apply() {
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = UIColor(named: "PaperRaised")
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(named: "InkSoft") ?? .secondaryLabel,
            .font: font
        ], for: .normal)
        let selectedFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(named: "Ink") ?? .label,
            .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: selectedFont)
        ], for: .selected)
    }
}
