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
                            }
                            .onDelete { model.delete(at: $0, in: ingredients, context: modelContext) }
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
