import SwiftUI
import SwiftData

struct FormulaListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Formula.name) private var formulas: [Formula]

    @State private var model = FormulaListViewModel()

    private var displayedFormulas: [Formula] {
        model.filtered(formulas)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if formulas.isEmpty {
                        ContentUnavailableView(
                            "No Formulas",
                            systemImage: "flask.roundbottom",
                            description: Text("Tap + to create your first formula.")
                        )
                    } else if displayedFormulas.isEmpty {
                        if !model.searchText.isEmpty {
                            ContentUnavailableView.search(text: model.searchText)
                        } else {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try adjusting your filters.")
                            )
                        }
                    } else {
                        List(selection: $model.selection) {
                            ForEach(displayedFormulas) { formula in
                                FormulaRowView(formula: formula)
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            model.delete(formula, context: modelContext)
                                        }
                                    }
                            }
                        }
                        .environment(\.editMode, $model.editMode)
                    }
                }
                .navigationTitle("Formulas")
                .searchable(text: $model.searchText, prompt: "Search formulas")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.editMode == .active {
                            Button("Delete", role: .destructive) {
                                model.deleteSelected(in: displayedFormulas, context: modelContext)
                            }
                            .disabled(model.selection.isEmpty)
                        }
                    }
                    if !formulas.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            EditButton()
                                .environment(\.editMode, $model.editMode)
                        }
                    }
                }

                if model.editMode == .inactive {
                    FloatingActionButton { model.showingAddFormula = true }
                }
            }
        }
        .alert(model.confirmingDelete.count == 1 ? "Delete Formula?" : "Delete Formulas?", isPresented: Binding(
            get: { !model.confirmingDelete.isEmpty },
            set: { if !$0 { model.confirmingDelete = [] } }
        )) {
            Button("Delete", role: .destructive) { model.confirmDelete(context: modelContext) }
            Button("Cancel", role: .cancel) { model.confirmingDelete = [] }
        } message: {
            let count = model.confirmingDelete.count
            let word = count == 1 ? "formula" : "formulas"
            Text("Deleting \(count) \(word) will also remove its ingredients and production history.")
        }
        .sheet(isPresented: $model.showingAddFormula) {
            NavigationStack {
                ContentUnavailableView(
                    "Coming Soon",
                    systemImage: "flask.roundbottom",
                    description: Text("Formula creation will be available in a future update.")
                )
                .navigationTitle("New Formula")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.showingAddFormula = false }
                    }
                }
            }
        }
    }
}
