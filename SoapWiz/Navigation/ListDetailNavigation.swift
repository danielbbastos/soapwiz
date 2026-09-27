import SwiftUI

/// When a tab shows its list beside the detail rather than pushing it (SW-89).
/// Decided by the window's width, not the device or orientation: an iPad Air 11"
/// is narrow in portrait (820 pt) and wide in landscape (1,180 pt), and a
/// narrow Split View or Stage Manager window falls back on its own.
enum ListDetailLayout {
    static let minimumWideWidth: CGFloat = 1_000

    /// Width of the list beside the detail.
    static let listColumnWidth: CGFloat = 380

    static func isWide(width: CGFloat) -> Bool {
        width >= minimumWideWidth
    }
}

/// One tab's navigation, in either layout. Narrow, the selected item is the
/// first screen pushed onto `path`; wide, it is the root of the detail column
/// and `path` holds only what was pushed from it.
///
/// Every open of an item goes through `show(_:)` so the selection is always
/// known: `NavigationPath` can't be read back, so it is the one thing that
/// carries across a width change. Anything pushed beyond the item is dropped
/// when the width changes.
@Observable
@MainActor
final class ListDetailNavigation<Item: Hashable> {
    var path = NavigationPath()
    private(set) var selection: Item?
    private(set) var isWide = false

    func show(_ item: Item) {
        selection = item
        path = isWide ? NavigationPath() : NavigationPath([item])
    }

    /// Whether `item`'s detail is open beside the list, for its row's tint.
    func isOpenBeside(_ item: Item) -> Bool {
        isWide && selection == item
    }

    func setWide(_ wide: Bool) {
        guard wide != isWide else { return }
        isWide = wide
        if wide {
            path = NavigationPath()
        } else {
            path = selection.map { NavigationPath([$0]) } ?? NavigationPath()
        }
    }

    /// Narrow, popping back to the list deselects: the item is off screen.
    func pathDidChange() {
        if !isWide && path.isEmpty {
            selection = nil
        }
    }

    /// Goes back to the list, and closes the detail too.
    func reset() {
        selection = nil
        path = NavigationPath()
    }

    /// Clears a selection that is no longer in `items`, so a deleted item's
    /// detail doesn't stay on screen over a detached model.
    func prune(keeping items: [Item]) {
        guard let selection, !items.contains(selection) else { return }
        reset()
    }
}
