import SwiftUI

enum LedgerRowHitArea {
    /// About a list row's vertical padding, so a tap near the top or bottom
    /// of the row still lands.
    static let outset: CGFloat = 12
}

/// A rectangle grown above and below by `LedgerRowHitArea.outset`, and not at
/// the sides, so a neighbour in the same row keeps its taps.
struct RowHeightHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -LedgerRowHitArea.outset))
    }
}

extension View {
    /// Makes a tap above or below the view, inside its list row, count as a
    /// tap on it. The view is one text line tall while its row is taller, so
    /// without this a tap in the row's padding does nothing. The cell's own
    /// bounds stop the reach at the row's edge, and the width is the view's
    /// own. The tap runs alongside the view's own, so the field still places
    /// its caret when touched directly.
    func tapsAcrossRowHeight(perform action: @escaping () -> Void) -> some View {
        contentShape(RowHeightHitShape())
            .simultaneousGesture(TapGesture().onEnded(action))
    }
}
