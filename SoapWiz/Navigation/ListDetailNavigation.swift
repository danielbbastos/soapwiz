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
/// carries across a width change. The item's detail moves from one stack to
/// the other, so anything pushed beyond it, and any sheet it presented, is
/// dropped when the width changes.
@Observable
@MainActor
final class ListDetailNavigation<Item: Hashable> {
    var path = NavigationPath()
    private(set) var selection: Item?
    private(set) var isWide = false

    /// The identity of the detail beside the list. It changes only when a
    /// different item opens, so re-pointing the selection at the same item's
    /// surviving row keeps the detail, and any sheet it has up.
    private(set) var detailID = UUID()

    func show(_ item: Item) {
        if item != selection { detailID = UUID() }
        selection = item
        path = isWide ? NavigationPath() : NavigationPath([item])
    }

    /// Points the selection at `item` without touching the screens or the
    /// detail's identity: for a row a duplicate merge replaced with its
    /// surviving copy, which the open detail has already moved to itself.
    func replaceSelection(with item: Item) {
        selection = item
    }

    /// Follows a duplicate merge onto `survivor`, the row that replaced the
    /// open item. A hidden survivor closes the detail instead, as hiding any
    /// open row does: the merge keeps a copy hidden on another device hidden,
    /// and since the set of hidden rows doesn't change, nothing else notices.
    ///
    /// `detailFollowed` says whether the open detail has already moved to the
    /// survivor itself, which it does for a merge run on this device. Then the
    /// detail is kept, with any sheet it has up. A merge run on another device
    /// arrives as a plain delete that the detail never hears about, so the
    /// survivor opens afresh rather than leave the detail on the deleted row.
    func followMerge(to survivor: Item, isHidden: Bool, detailFollowed: Bool) {
        if isHidden {
            reset()
        } else if detailFollowed {
            replaceSelection(with: survivor)
        } else {
            show(survivor)
        }
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

    /// Closes the detail when it shows one of `items`. Called before those items
    /// are deleted, not after: once the list stops showing a row, the detail
    /// beside it can still render the deleted model for a frame, and reading a
    /// deleted model traps.
    func close(ifShowingAnyOf items: [Item]) {
        guard let selection, items.contains(selection) else { return }
        reset()
    }

    /// Clears a selection that is no longer in `items`, for deletions that
    /// arrive without passing through the list, such as from another device.
    func prune(keeping items: [Item]) {
        guard let selection, !items.contains(selection) else { return }
        reset()
    }
}
