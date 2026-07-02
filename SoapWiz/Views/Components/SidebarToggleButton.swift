import SwiftUI

/// Replaces the system sidebar toggle, whose glyph visibly drifts out of its
/// button while the split-view columns animate on iPadOS 26. Owning views
/// host it as a *conditional* toolbar item (`if` inside the toolbar builder,
/// gated on size class + column visibility) — an unconditional item would
/// draw its empty glass chrome even while hidden.
struct SidebarToggleButton: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    /// `true` for the detail-side instance shown while collapsed; `false` for
    /// the sidebar-side instance shown while open.
    var expandsSidebar = false

    var body: some View {
        Button {
            withAnimation {
                columnVisibility = expandsSidebar ? .all : .detailOnly
            }
        } label: {
            Image(systemName: "sidebar.leading")
        }
    }
}

/// The conditional toolbar hosting for `SidebarToggleButton`: present only in
/// its own settled state so the toolbar never draws empty button chrome.
struct SidebarToggleToolbarItem: ToolbarContent {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    /// Computed by the owning view from its own `horizontalSizeClass` — the
    /// size class inside a sidebar column is compact even on iPad.
    let isActive: Bool
    var expandsSidebar = false

    private var isInOwnState: Bool {
        expandsSidebar ? columnVisibility == .detailOnly : columnVisibility != .detailOnly
    }

    var body: some ToolbarContent {
        if isActive && isInOwnState {
            ToolbarItem(placement: expandsSidebar ? .topBarLeading : .topBarTrailing) {
                SidebarToggleButton(columnVisibility: $columnVisibility, expandsSidebar: expandsSidebar)
            }
        }
    }
}
