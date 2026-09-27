import SwiftUI

/// A tab's list and its detail: one stack where the detail is pushed, or the
/// list beside the detail on a wide window (SW-89).
///
/// `list` is the stack's root in both layouts, with its own toolbar, sheets and
/// destinations; the narrow layout pushes through those. The wide detail column
/// is a stack of its own, so `detail` attaches whatever the detail pushes.
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
        Group {
            if navigation.isWide {
                HStack(spacing: 0) {
                    NavigationStack {
                        list()
                    }
                    .frame(width: ListDetailLayout.listColumnWidth)
                    Divider()
                        .ignoresSafeArea()
                    NavigationStack(path: $navigation.path) {
                        detailRoot
                    }
                }
            } else {
                NavigationStack(path: $navigation.path) {
                    list()
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ListDetailLayout.isWide(width: proxy.size.width)
        } action: { wide in
            navigation.setWide(wide)
        }
        .onChange(of: navigation.path) {
            navigation.pathDidChange()
        }
    }

    /// `.id` gives each item a fresh detail, so state a detail screen seeds
    /// from its item on creation isn't carried over to the next one.
    @ViewBuilder
    private var detailRoot: some View {
        if let item = navigation.selection {
            detail(item)
                .id(item)
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
    /// The row background of a list that can sit beside its detail: tinted for
    /// the item open beside it, the card colour otherwise. A button row rather
    /// than `List(selection:)`, which on iPadOS 26 draws a bordered capsule no
    /// row background can hide.
    func listDetailRowBackground(isSelected: Bool) -> some View {
        listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.cardBackground)
    }
}
