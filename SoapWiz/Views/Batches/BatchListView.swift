import SwiftUI
import SwiftData

/// History tab: every batch ever produced, newest first under a header for the
/// month it was made in. Read-only — batches are created from a recipe's detail
/// screen, not from here.
struct BatchListView: View {
    @Query private var batches: [Batch]
    @Environment(AppNavigation.self) private var navigation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTourSandbox) private var isTourSandbox

    @State private var searchText = ""
    @State private var dataTransfer = DataTransferViewModel()
    @State private var showsBackupNudge = false

    private let nudgeState = BackupNudgeState()

    private var exportError: Binding<Bool> {
        Binding(
            get: { dataTransfer.errorMessage != nil },
            set: { if !$0 { dataTransfer.errorMessage = nil } }
        )
    }

    private func refreshBackupNudge() {
        let now = Date.now
        let context = BackupNudgePolicy.Context(
            hasCloudCopy: BackupNudgePolicy.hasCloudCopy(ModelContainerFactory.activeStore),
            isTourSandbox: isTourSandbox,
            batchCount: batches.count
        )
        BackupNudgePolicy.recordFirstEligibleIfNeeded(context, state: nudgeState, now: now)
        showsBackupNudge = BackupNudgePolicy.shouldShow(context, state: nudgeState, now: now, calendar: .current)
    }

    private func dismissBackupNudge() {
        nudgeState.lastDismissDate = .now
        withAnimation { showsBackupNudge = false }
    }

    private var displayedSections: [BatchMonthSection] {
        BatchHistoryViewModel.monthSections(
            BatchHistoryViewModel.filtered(batches, matching: searchText)
        )
    }

    /// A `Button` rather than a `NavigationLink(value:)`, so every open goes
    /// through `show(_:)` and the selection survives a width change. The
    /// chevron a link would draw is left out, as on the other lists.
    ///
    /// `isTourTarget` marks the newest batch, the one the onboarding tour lights.
    private func row(_ batch: Batch, position: LedgerSheetPosition, isTourTarget: Bool) -> some View {
        Button {
            navigation.history.show(batch)
        } label: {
            BatchRowView(batch: batch)
                .contentShape(Rectangle())
        }
        .ledgerListDetailRow(isSelected: navigation.history.isOpenBeside(batch), position: position)
        .tourCardAnchor(isTourTarget ? .batchRow : nil)
    }

    var body: some View {
        // Filtered and grouped once per pass; several places below need it.
        let displayed = displayedSections
        ListDetailContainer(
            navigation: navigation.history,
            placeholder: "Select a Batch",
            placeholderSymbol: "clock.arrow.circlepath",
            placeholderDescription: "Choose a batch from the list to see its record here.",
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
                        if showsBackupNudge {
                            Section {
                                BackupNudgeCard(
                                    onExport: { dataTransfer.export(from: modelContext) },
                                    onDismiss: dismissBackupNudge
                                )
                                .ledgerSheetRow(position: .only)
                            }
                        }
                        ForEach(displayed) { section in
                            Section {
                                ForEach(Array(section.batches.enumerated()), id: \.element.id) { index, batch in
                                    row(
                                        batch,
                                        position: .position(index: index, count: section.batches.count),
                                        isTourTarget: index == 0 && section.id == displayed.first?.id
                                    )
                                }
                            } header: {
                                HoneyLedgerSectionLabel(section.title)
                            }
                        }
                    }
                }
            }
            .readableWidth()
            .sheet(item: $dataTransfer.exportFile) { file in
                ShareSheet(items: [file.url]) { completed in
                    dataTransfer.shareFinished(completed: completed)
                    if completed { withAnimation { showsBackupNudge = false } }
                }
            }
            .alert("Something went wrong", isPresented: exportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataTransfer.errorMessage ?? "")
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .ledgerLargeTitle(subtitle: BatchCountSummary(counting: batches).line)
            .ledgerBackground(sunken: navigation.history.isWide)
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
        .onAppear { refreshBackupNudge() }
        .onChange(of: batches.isEmpty) { refreshBackupNudge() }
    }
}
