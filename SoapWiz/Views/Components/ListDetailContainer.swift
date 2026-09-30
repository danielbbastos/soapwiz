import SwiftUI

/// A tab's list and its detail: one stack where the detail is pushed, or the
/// list beside the detail on a wide window (SW-89).
///
/// `list` is the stack's root in both layouts, with its own toolbar, sheets and
/// destinations; the narrow layout pushes through those. The wide detail column
/// is a stack of its own, so `detail` attaches whatever the detail pushes.
///
/// The list's stack sits at the same place in both layouts, only narrowing to
/// a column, so a width change keeps the list's scroll position and anything
/// the list presented. The detail can't be kept the same way: it moves from
/// the list's stack to a stack of its own.
struct ListDetailContainer<Item: Hashable, ListContent: View, Detail: View>: View {
    @Bindable var navigation: ListDetailNavigation<Item>
    let placeholder: LocalizedStringKey
    let placeholderSymbol: String
    /// False while the list is empty: it then says so itself, and a "Select…"
    /// beside it would ask for something there is nothing to choose from.
    var hasItems = true
    @ViewBuilder let list: () -> ListContent
    @ViewBuilder let detail: (Item) -> Detail

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack(path: listPath) {
                list()
            }
            .frame(width: navigation.isWide ? ListDetailLayout.listColumnWidth : nil)
            if navigation.isWide {
                Divider()
                    .ignoresSafeArea()
                NavigationStack(path: $navigation.path) {
                    detailRoot
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ListDetailLayout.isWide(width: proxy.size.width)
        } action: { wide in
            navigation.setWide(wide)
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ListDetailLayout.fabSitsBesideTabBar(width: proxy.size.width)
        } action: { besideTabBar in
            navigation.fabBesideTabBar = besideTabBar
        }
        .onChange(of: navigation.path) {
            navigation.pathDidChange()
        }
    }

    /// Narrow, the tab's path. Wide, always empty: items open beside the list,
    /// and `path` then belongs to the detail's stack.
    private var listPath: Binding<NavigationPath> {
        Binding(
            get: { navigation.isWide ? NavigationPath() : navigation.path },
            set: { if !navigation.isWide { navigation.path = $0 } }
        )
    }

    /// `.id` gives each item a fresh detail, so state a detail screen seeds
    /// from its item on creation isn't carried over to the next one. Keyed by
    /// `detailID` rather than the item, so a merge re-pointing the selection
    /// doesn't rebuild the detail.
    @ViewBuilder
    private var detailRoot: some View {
        if let item = navigation.selection {
            detail(item)
                .id(navigation.detailID)
        } else {
            Group {
                if hasItems {
                    ContentUnavailableView(placeholder, systemImage: placeholderSymbol)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .warmBackground()
        }
    }
}

extension View {
    /// A row of a list that can sit beside its detail: tinted for the item open
    /// beside it, the card colour otherwise, and marked selected for VoiceOver.
    /// A button row rather than `List(selection:)`, which on iPadOS 26 draws a
    /// bordered capsule no row background can hide, and which would otherwise
    /// announce the selection itself.
    func listDetailRow(isSelected: Bool) -> some View {
        listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.cardBackground)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
