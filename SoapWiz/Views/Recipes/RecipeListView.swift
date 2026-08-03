import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var model = RecipeListViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showingImport = false

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
                                .listRowBackground(Color.cardBackground)
                            }
                        }
                    }
                }
                .navigationTitle("Recipes")
                .navigationBarTitleDisplayMode(.inline)
                .warmNavigationTitle("Recipes")
                .warmBackground()
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
                .navigationDestination(for: Bool.self) { _ in
                    RecipeFormView(onSave: { _ in
                        navigationPath = NavigationPath()
                    })
                }
                .navigationDestination(for: RecipeSeed.self) { seed in
                    RecipeFormView(seed: seed, onSave: { _ in
                        navigationPath = NavigationPath()
                    })
                }
                .navigationDestination(for: PreparedRecipeImport.self) { prepared in
                    RecipeFormView(importDraft: prepared, onSave: { _ in
                        navigationPath = NavigationPath()
                    })
                }
                .sheet(isPresented: $showingImport) {
                    RecipeImportView { prepared in
                        navigationPath.append(prepared)
                    }
                }

                // Import is offered only when the on-device model can actually
                // run it. A feature that fails on tap is worse than one that
                // isn't there.
                ExpandableFloatingActionButton(
                    primaryAction: { navigationPath.append(true) },
                    secondaryActions: RecipeImportAvailability.current.isAvailable
                        ? [FABAction(label: "Import Recipe", systemImage: "doc.text.viewfinder") { showingImport = true }]
                        : []
                )
            }
        }
        // Honour a seeded-recipe request from the inventory selection flow: open
        // the form pre-filled, then consume the request so it doesn't re-fire.
        // `initial: true` covers the first launch, when this tab is created lazily
        // *after* the seed is set and a plain change wouldn't fire.
        .onChange(of: nav.pendingRecipeSeed, initial: true) { _, seed in
            guard let seed else { return }
            navigationPath.append(seed)
            nav.pendingRecipeSeed = nil
        }
    }
}
