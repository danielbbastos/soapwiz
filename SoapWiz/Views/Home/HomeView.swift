import Combine
import SwiftUI

struct HomeView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.isTourSandbox) private var isTourSandbox
    @Environment(RecipeRows.self) private var recipeRows
    @Environment(BatchRows.self) private var batchRows
    @Environment(InventoryRows.self) private var inventoryRows
    @Environment(ShoppingListRows.self) private var shoppingList
    @State private var isWide = false
    @State private var now = Date.now
    @State private var hasCards = true

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
            .ledgerLargeTitle(subtitle: dateLine, margin: titleMargin)
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

    private var titleMargin: (CGFloat) -> CGFloat? {
        let isFirstRun = isFirstRun
        return { HomeLayout.titleMargin(width: $0, isFirstRun: isFirstRun) }
    }

    /// Not in the tour sandbox, where restoring a backup must never be reachable.
    private var isFirstRun: Bool {
        !isTourSandbox && HomeFirstRun.isEmpty(
            recipes: recipeRows.recipes,
            batches: batchRows.batches,
            shoppingItems: shoppingList.items,
            ingredients: inventoryRows.ingredients,
            purchases: inventoryRows.purchases
        )
    }

    private var scroll: some View {
        ScrollView {
            Group {
                if isFirstRun {
                    HomeFirstRunView()
                } else {
                    VStack(spacing: HomeLayout.spacing) {
                        VStack(spacing: 0) {
                            HomeGrid(isWide: isWide) {
                                NeedsAttentionCard()
                                HomeCuringCard()
                                YouCanMakeCard()
                                ShoppingListCard()
                            }
                            .transformPreference(HomeCardShownKey.self) { $0 = $0 ?? false }
                            .onPreferenceChange(HomeCardShownKey.self) { shown in
                                let anyShown = shown ?? true
                                MainActor.assumeIsolated { hasCards = anyShown }
                            }
                            if !hasCards {
                                placeholder
                            }
                        }
                        if isWide {
                            InsightsSection(isWide: true)
                                .frame(maxWidth: HomeLayout.maximumWidth)
                                .frame(maxWidth: .infinity)
                        } else {
                            InsightsSection(isWide: false)
                        }
                    }
                }
            }
            .padding(HomeLayout.contentPadding)
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
