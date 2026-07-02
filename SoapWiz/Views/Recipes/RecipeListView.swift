import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var model = RecipeListViewModel()
    @State private var selectedRecipe: Recipe?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var creatingRecipe = false
    @State private var creatingSeed: RecipeSeed?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes",
                        systemImage: "function",
                        description: Text("Tap + to create your first recipe.")
                    )
                } else if horizontalSizeClass == .compact {
                    // Compact needs the selection binding: it is what makes
                    // the collapsed split view push the detail screen.
                    List(selection: $selectedRecipe) {
                        ForEach(recipes) { recipe in
                            RecipeRowView(recipe: recipe)
                                .tag(recipe)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        model.delete(recipe, context: modelContext)
                                    }
                                }
                                .listRowBackground(Color.cardBackground)
                        }
                    }
                } else {
                    // Regular drives selection manually: a bound List draws
                    // the system's bordered-capsule indicator, which fights
                    // the row-background wash used as the selection style.
                    List {
                        ForEach(recipes) { recipe in
                            Button {
                                selectedRecipe = recipe
                            } label: {
                                RecipeRowView(recipe: recipe)
                                    // Make the whole row tappable, including
                                    // the gap between text and trailing detail.
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    model.delete(recipe, context: modelContext)
                                }
                            }
                            .listRowBackground(
                                selectedRecipe == recipe
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.cardBackground
                            )
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Recipes")
            .warmBackground()
            .toolbar {
                SidebarToggleToolbarItem(columnVisibility: $columnVisibility, isActive: horizontalSizeClass == .regular)
            }
            .toolbar(removing: .sidebarToggle)
            .overlay(alignment: .bottomTrailing) {
                FloatingActionButton {
                    selectedRecipe = nil
                    creatingRecipe = true
                    columnVisibility = .detailOnly
                }
            }
        } detail: {
            Group {
                if creatingRecipe {
                    NavigationStack {
                        RecipeFormView(onSave: { _ in
                            creatingRecipe = false
                            columnVisibility = .all
                        })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    creatingRecipe = false
                                    columnVisibility = .all
                                }
                            }
                        }
                    }
                } else if let creatingSeed {
                    NavigationStack {
                        RecipeFormView(seed: creatingSeed, onSave: { _ in
                            self.creatingSeed = nil
                            columnVisibility = .all
                        })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    self.creatingSeed = nil
                                    columnVisibility = .all
                                }
                            }
                        }
                    }
                } else if let selectedRecipe {
                    NavigationStack {
                        RecipeDetailView(recipe: selectedRecipe)
                            .id(selectedRecipe.persistentModelID)
                            .toolbar {
                                SidebarToggleToolbarItem(
                                columnVisibility: $columnVisibility,
                                isActive: horizontalSizeClass == .regular,
                                expandsSidebar: true
                            )
                            }
                    }
                } else {
                    NavigationStack {
                        ContentUnavailableView(
                            "Select a Recipe",
                            systemImage: "function",
                            description: Text("Choose a recipe from the list.")
                        )
                        .toolbar {
                            SidebarToggleToolbarItem(
                                columnVisibility: $columnVisibility,
                                isActive: horizontalSizeClass == .regular,
                                expandsSidebar: true
                            )
                        }
                    }
                }
            }
            // The create flows get no toggle: they own the detail column with
            // their own Cancel button in that toolbar slot.
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        // Honour a seeded-recipe request from the inventory selection flow: open
        // the form pre-filled, then consume the request so it doesn't re-fire.
        // `initial: true` covers the first launch, when this tab is created lazily
        // *after* the seed is set and a plain change wouldn't fire.
        .onChange(of: nav.pendingRecipeSeed, initial: true) { _, seed in
            guard let seed else { return }
            selectedRecipe = nil
            creatingRecipe = false
            creatingSeed = seed
            columnVisibility = .detailOnly
            nav.pendingRecipeSeed = nil
        }
    }
}
