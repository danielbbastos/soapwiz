import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var model = IngredientListViewModel()

    var body: some View {
        NavigationStack {
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
                                NavigationLink(destination: IngredientDetailView(ingredient: ingredient)) {
                                    IngredientRowView(ingredient: ingredient)
                                }
                            }
                            .onDelete { model.delete(at: $0, in: ingredients, context: modelContext) }
                        }
                        .environment(\.editMode, $model.editMode)
                    }
                }
                .navigationTitle("Inventory")
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
        .sheet(isPresented: $model.showingAddIngredient) {
            IngredientFormView()
        }
    }
}
