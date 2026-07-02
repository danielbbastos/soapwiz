import SwiftUI
import SwiftData

/// History tab: every batch ever produced, newest first. Read-only — batches
/// are created from a recipe's detail screen, not from here.
struct BatchListView: View {
    @Query private var batches: [Batch]
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedBatch: Batch?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var sortedBatches: [Batch] {
        BatchHistoryViewModel.sortedNewestFirst(batches)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if batches.isEmpty {
                    ContentUnavailableView(
                        "No Batches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Batches you produce from a recipe will appear here.")
                    )
                } else {
                    List(selection: $selectedBatch) {
                        ForEach(sortedBatches) { batch in
                            BatchRowView(batch: batch)
                                .tag(batch)
                                .listRowBackground(Color.cardBackground)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("History")
            .warmBackground()
            .toolbar {
                SidebarToggleToolbarItem(columnVisibility: $columnVisibility, isActive: horizontalSizeClass == .regular)
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if let selectedBatch {
                    NavigationStack {
                        BatchDetailView(batch: selectedBatch)
                            .id(selectedBatch.persistentModelID)
                            .navigationDestination(for: Recipe.self) { recipe in
                                RecipeDetailView(recipe: recipe)
                            }
                            .toolbar {
                                SidebarToggleToolbarItem(
                                columnVisibility: $columnVisibility,
                                isActive: horizontalSizeClass == .regular,
                                expandsSidebar: true
                            )
                            }
                    }
                } else {
                    NavigationStack {
                        ContentUnavailableView(
                            "Select a Batch",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Choose a batch from the list.")
                        )
                        .toolbar {
                            SidebarToggleToolbarItem(
                                columnVisibility: $columnVisibility,
                                isActive: horizontalSizeClass == .regular,
                                expandsSidebar: true
                            )
                        }
                    }
                }
            }
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        // `initial: true` covers the first hand-off, when this tab is created
        // lazily *after* `pendingBatch` is set and a plain change wouldn't fire.
        .onChange(of: navigation.pendingBatch, initial: true) { _, batch in
            if let batch {
                selectedBatch = batch
                navigation.pendingBatch = nil
            }
        }
    }
}
