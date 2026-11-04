import SwiftUI

/// What the list adds above its first row. Measured: without taking it off, a
/// row as tall as the visible area overflows by this much and the list scrolls.
private let listTopSpacing: CGFloat = 20

/// A list screen's empty state, drawn as one row of its own `List` instead of a
/// view that replaces the `List`.
///
/// Swapping the scroll view out leaves the UIKit large title laid out against
/// one that is gone: the title settles in the wrong place, or the subtitle and
/// search field are overdrawn. Keeping the `List` and putting the empty state
/// inside it avoids that, so a list screen keeps its `List` whatever it shows.
///
/// Use `measuringListHeight(_:)` on the `List` and `listEmptyStateRow(listHeight:)`
/// on the empty state inside it:
///
///     List {
///         if items.isEmpty { MyEmptyState().listEmptyStateRow(listHeight: listHeight) }
///         ForEach(items) { ... }
///     }
///     .measuringListHeight($listHeight)
extension View {
    /// Fills the visible part of the list, so the empty state sits centred
    /// between the header strip and the tab bar, with nothing drawn around it.
    /// `listHeight` comes from `measuringListHeight(_:)`.
    func listEmptyStateRow(listHeight: CGFloat) -> some View {
        frame(height: max(listHeight, 280))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    /// Reports the height of the list's visible scroll area (its size less the
    /// insets under the bars and the header strip) into `height`, and stops it
    /// bouncing while its content fits, as an empty state's does.
    func measuringListHeight(_ height: Binding<CGFloat>) -> some View {
        scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            } action: { _, newHeight in
                height.wrappedValue = newHeight - listTopSpacing
            }
    }
}
