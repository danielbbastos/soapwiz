import Combine
import SwiftUI

struct HomeView: View {
    @Environment(AppNavigation.self) private var navigation
    @State private var isWide = false
    @State private var now = Date.now

    private var dateLine: String {
        now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.homePath) {
            content
            .environment(\.homeNow, now)
            .onGeometryChange(for: Bool.self) { proxy in
                ListDetailLayout.isWide(width: proxy.size.width)
            } action: { isWide = $0 }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .ledgerLargeTitle(subtitle: dateLine)
            .ledgerBackground()
        }
        .onAppear { now = .now }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
                .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
        ) { _ in
            now = .now
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
            VStack(spacing: HomeLayout.spacing) {
                HomeGrid(isWide: isWide) {
                    NeedsAttentionCard()
                    HomeCuringCard()
                    YouCanMakeCard()
                    placeholder
                    if !isWide {
                        InsightsSection(isWide: false)
                    }
                }
                if isWide {
                    InsightsSection(isWide: true)
                        .frame(maxWidth: HomeLayout.maximumWidth)
                        .frame(maxWidth: .infinity)
                }
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
