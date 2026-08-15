import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]

    @State private var model = RecipeListViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showingImport = false

    // Favourites can't be part of the `@Query` sort: `SortDescriptor` has no `Bool`
    // overload, so the pinning is applied here over the alphabetical fetch.
    private var displayedRecipes: [Recipe] {
        model.filtered(recipes.favoritesFirst)
    }

    private func row(_ recipe: Recipe) -> some View {
        NavigationLink(value: recipe) {
            RecipeRowView(recipe: recipe) {
                model.toggleFavorite(recipe)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                model.delete(recipe, context: modelContext)
            }
        }
        .contextMenu { rowMenu(recipe) }
        .listRowBackground(Color.cardBackground)
    }

    /// Long-press actions on a row. Filing lives here as well as in the form
    /// because sorting a pile of recipes into collections is a batch job, and
    /// opening the whole editor for each one is the slow way to do it.
    @ViewBuilder
    private func rowMenu(_ recipe: Recipe) -> some View {
        Button {
            model.filingRecipe = recipe
        } label: {
            Label("Collections…", systemImage: "square.stack")
        }
        Button {
            model.duplicate(recipe, among: recipes, context: modelContext)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            model.copyToPasteboard(recipe)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) {
            model.delete(recipe, context: modelContext)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    var body: some View {
        // Filtered once per pass: the branch below and the list itself both need
        // it, and the filter walks every recipe's collections.
        let displayed = displayedRecipes
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if recipes.isEmpty {
                        ContentUnavailableView(
                            "No Recipes",
                            systemImage: "function",
                            description: Text("Tap + to create your first recipe.")
                        )
                    } else if displayed.isEmpty {
                        ContentUnavailableView {
                            Label("No Matching Recipes", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No recipes are filed under the selected collections.")
                        } actions: {
                            Button("Clear Filters") { model.clearFilters() }
                        }
                    } else {
                        List {
                            ForEach(displayed) { row($0) }
                        }
                        // The chips already stand off the list on their own;
                        // the scroll view's default top margin on top of that
                        // left the two looking unrelated.
                        .contentMargins(.top, collections.isEmpty ? nil : 0, for: .scrollContent)
                    }
                }
                .navigationTitle("Recipes")
                .navigationBarTitleDisplayMode(.inline)
                .warmNavigationTitle("Recipes")
                .warmBackground()
                // No background of its own, so the list keeps scrolling under
                // the navigation bar's material rather than under a flat band.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !collections.isEmpty {
                        RecipeCollectionFilterBar(collections: collections, model: model)
                    }
                }
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
                .sheet(item: $model.filingRecipe) { recipe in
                    RecipeCollectionsPickerSheet(recipe: recipe) { collection in
                        model.toggleMembership(of: recipe, in: collection)
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
        // A collection deleted here or merged away by `DuplicateMerger` would
        // otherwise leave a selection matching nothing, and an empty list with
        // no visible chip to explain it.
        .onChange(of: collections) {
            model.pruneSelectedCollections(against: collections)
        }
    }
}
