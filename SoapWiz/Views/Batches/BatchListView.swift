import SwiftUI
import SwiftData

/// History tab: every batch ever produced, newest first under a header for the
/// month it was made in. Read-only — batches are created from a recipe's detail
/// screen, not from here.
struct BatchListView: View {
    @Query private var batches: [Batch]
    @Environment(AppNavigation.self) private var navigation

    @State private var searchText = ""

    private var displayedSections: [BatchMonthSection] {
        BatchHistoryViewModel.monthSections(
            BatchHistoryViewModel.filtered(batches, matching: searchText)
        )
    }

    /// A `Button` rather than a `NavigationLink(value:)`, so every open goes
    /// through `show(_:)` and the selection survives a width change. The
    /// chevron a link would draw is left out, as on the other lists.
    private func row(_ batch: Batch) -> some View {
        Button {
            navigation.history.show(batch)
        } label: {
            BatchRowView(batch: batch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listDetailRow(isSelected: navigation.history.isOpenBeside(batch))
    }

    var body: some View {
        // Filtered and grouped once per pass; several places below need it.
        let displayed = displayedSections
        ListDetailContainer(
            navigation: navigation.history,
            placeholder: "Select a Batch",
            placeholderSymbol: "clock.arrow.circlepath",
            hasItems: !displayed.isEmpty
        ) {
            Group {
                if batches.isEmpty {
                    ContentUnavailableView(
                        "No Batches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Batches you produce from a recipe will appear here.")
                    )
                } else if displayed.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(displayed) { section in
                            Section(section.title) {
                                ForEach(section.batches) { row($0) }
                            }
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("History")
            .warmBackground()
            .searchHeader("Search batches", text: $searchText, showsList: !displayed.isEmpty)
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
