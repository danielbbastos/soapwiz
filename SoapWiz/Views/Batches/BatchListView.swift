import SwiftUI
import SwiftData

/// History tab: every batch ever produced, newest first. Read-only — batches
/// are created from a recipe's detail screen, not from here.
struct BatchListView: View {
    @Query private var batches: [Batch]
    @Environment(AppNavigation.self) private var navigation

    private var sortedBatches: [Batch] {
        BatchHistoryViewModel.sortedNewestFirst(batches)
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.historyPath) {
            Group {
                if batches.isEmpty {
                    ContentUnavailableView(
                        "No Batches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Batches you produce from a recipe will appear here.")
                    )
                } else {
                    List {
                        ForEach(sortedBatches) { batch in
                            NavigationLink(value: batch) {
                                BatchRowView(batch: batch)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Batch.self) { batch in
                BatchDetailView(batch: batch)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }
}
