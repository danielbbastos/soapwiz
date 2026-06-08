import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var model = RecipeListViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if recipes.isEmpty {
                        ContentUnavailableView(
                            "No Recipes",
                            systemImage: "function",
                            description: Text("Tap + to create your first recipe.")
                        )
                    } else {
                        List {
                            ForEach(recipes) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeRowView(recipe: recipe)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        model.delete(recipe, context: modelContext)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Recipes")
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
                .navigationDestination(for: Bool.self) { _ in
                    RecipeFormView(onSave: { _ in
                        navigationPath = NavigationPath()
                    })
                }

                FloatingActionButton {
                    navigationPath.append(true)
                }
            }
        }
    }
}
