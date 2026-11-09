import SwiftUI

struct HomeView: View {
    @Environment(AppNavigation.self) private var navigation
    @State private var isWide = false

    private var dateLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.homePath) {
            content
            .onGeometryChange(for: Bool.self) { proxy in
                ListDetailLayout.isWide(width: proxy.size.width)
            } action: { isWide = $0 }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .ledgerLargeTitle(subtitle: dateLine)
            .ledgerBackground()
        }
    }

    /// The wide grid caps itself at `HomeLayout.maximumWidth`, so the narrow
    /// column's readable width must not narrow it first.
    @ViewBuilder
    private var content: some View {
        if isWide {
            scroll
        } else {
            scroll.readableWidth(inset: 16)
        }
    }

    private var scroll: some View {
        ScrollView {
            HomeGrid(isWide: isWide) {
                placeholder
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var placeholder: some View {
        HoneyLedgerEmptyState(
            "Your workshop at a glance",
            systemImage: "house",
            description: "Curing batches, stock that needs attention and what you can make will show here."
        )
        .padding(.vertical, 48)
    }
}
