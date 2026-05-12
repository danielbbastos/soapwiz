import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var model = IngredientListViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if ingredients.isEmpty {
                        ContentUnavailableView(
                            "No Ingredients",
                            systemImage: "flask",
                            description: Text("Tap + to add your first ingredient.")
                        )
                    } else {
                        List(selection: $model.selection) {
                            ForEach(ingredients) { ingredient in
                                NavigationLink(value: ingredient) {
                                    IngredientRowView(ingredient: ingredient)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        model.delete(ingredient, context: modelContext)
                                    }
                                }
                            }
                        }
                        .environment(\.editMode, $model.editMode)
                    }
                }
                .navigationTitle("Inventory")
                .navigationDestination(for: Ingredient.self) { ingredient in
                    IngredientDetailView(
                        ingredient: ingredient,
                        autoAddBatch: model.pendingIngredient?.persistentModelID == ingredient.persistentModelID
                    )
                    .onAppear { model.pendingIngredient = nil }
                }
                .toolbar {
                    if !ingredients.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            if model.editMode == .active {
                                Button("Delete", role: .destructive) {
                                    model.deleteSelected(in: ingredients, context: modelContext)
                                }
                                .disabled(model.selection.isEmpty)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            EditButton()
                                .environment(\.editMode, $model.editMode)
                        }
                    }
                }

                if model.editMode == .inactive {
                    FloatingActionButton { model.showingAddIngredient = true }
                }
            }
        }
        .alert(model.confirmingDelete.count == 1 ? "Delete Ingredient?" : "Delete Ingredients?", isPresented: Binding(
            get: { !model.confirmingDelete.isEmpty },
            set: { if !$0 { model.confirmingDelete = [] } }
        )) {
            Button("Delete", role: .destructive) { model.confirmDelete(context: modelContext) }
            Button("Cancel", role: .cancel) { model.confirmingDelete = [] }
        } message: {
            let batchCount = model.confirmingDelete.reduce(0) { $0 + $1.batches.count }
            let ingredientWord = model.confirmingDelete.count == 1 ? "ingredient" : "ingredients"
            let batchWord = batchCount == 1 ? "batch" : "batches"
            Text("Deleting \(model.confirmingDelete.count) \(ingredientWord) will also delete \(batchCount) \(batchWord).")
        }
        .sheet(isPresented: $model.showingAddIngredient, onDismiss: {
            if let ingredient = model.pendingIngredient {
                navigationPath.append(ingredient)
            }
        }) {
            IngredientFormView(onSave: { ingredient in
                model.pendingIngredient = ingredient
            })
        }
    }
}
