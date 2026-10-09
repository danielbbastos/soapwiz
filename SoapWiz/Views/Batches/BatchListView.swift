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
    private func row(_ batch: Batch, position: LedgerSheetPosition) -> some View {
        Button {
            navigation.history.show(batch)
        } label: {
            BatchRowView(batch: batch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ledgerListDetailRow(isSelected: navigation.history.isOpenBeside(batch), position: position)
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
                    HoneyLedgerEmptyState(
                        "No Batches",
                        systemImage: "clock.arrow.circlepath",
                        description: "Batches you produce from a recipe will appear here."
                    )
                } else if displayed.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(displayed) { section in
                            Section {
                                ForEach(Array(section.batches.enumerated()), id: \.element.id) { index, batch in
                                    row(batch, position: .position(index: index, count: section.batches.count))
                                }
                            } header: {
                                HoneyLedgerSectionLabel(section.title)
                            }
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .ledgerLargeTitle(subtitle: BatchCountSummary(counting: batches).line)
            .ledgerBackground()
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
