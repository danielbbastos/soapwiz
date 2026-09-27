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

    /// A `Button` rather than a `NavigationLink(value:)`, so every open goes
    /// through `show(_:)` and the selection survives a width change. The
    /// chevron a link would draw is drawn by hand, and only where the row
    /// pushes.
    private func row(_ batch: Batch) -> some View {
        Button {
            navigation.history.show(batch)
        } label: {
            HStack {
                BatchRowView(batch: batch)
                if !navigation.history.isWide {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listDetailRow(isSelected: navigation.history.isOpenBeside(batch))
    }

    var body: some View {
        ListDetailContainer(
            navigation: navigation.history,
            placeholder: "Select a Batch",
            placeholderSymbol: "clock.arrow.circlepath",
            hasItems: !batches.isEmpty
        ) {
            Group {
                if batches.isEmpty {
                    ContentUnavailableView(
                        "No Batches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Batches you produce from a recipe will appear here.")
                    )
                } else {
                    List {
                        ForEach(sortedBatches) { row($0) }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("History")
            .warmBackground()
            .navigationDestination(for: Batch.self) { batch in
                BatchDetailView(batch: batch)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        } detail: { batch in
            BatchDetailView(batch: batch)
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
        }
        .onChange(of: batches) {
            navigation.history.prune(keeping: batches)
        }
    }
}
