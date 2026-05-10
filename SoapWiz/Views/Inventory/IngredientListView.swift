import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var showingAddIngredient = false
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<PersistentIdentifier> = []

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
                        List(selection: $selection) {
                            ForEach(ingredients) { ingredient in
                                NavigationLink(destination: IngredientDetailView(ingredient: ingredient)) {
                                    IngredientRowView(ingredient: ingredient)
                                }
                            }
                            .onDelete(perform: deleteIngredients)
                        }
                        .environment(\.editMode, $editMode)
                    }
                }
                .navigationTitle("Inventory")
                .toolbar {
                    if !ingredients.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            if editMode == .active {
                                Button("Delete", role: .destructive) {
                                    deleteSelected()
                                }
                                .disabled(selection.isEmpty)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            EditButton()
                                .environment(\.editMode, $editMode)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: CategoryListView()) {
                            Image(systemName: "tag")
                        }
                    }
                }

                if editMode == .inactive {
                    FloatingActionButton { showingAddIngredient = true }
                }
            }
        }
        .sheet(isPresented: $showingAddIngredient) {
            IngredientFormView()
        }
    }

    private func deleteIngredients(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(ingredients[index])
        }
    }

    private func deleteSelected() {
        for id in selection {
            if let match = ingredients.first(where: { $0.persistentModelID == id }) {
                modelContext.delete(match)
            }
        }
        selection.removeAll()
        editMode = .inactive
    }
}
