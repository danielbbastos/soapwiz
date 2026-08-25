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

    /// A `Button` rather than a `NavigationLink` purely to drop the disclosure
    /// chevron: a link used as a row's root always draws one, and there is no
    /// modifier to suppress it. The push is the same, just issued by hand.
    /// `.plain` keeps the row from taking on button tinting; the star inside
    /// stays tappable because it is `.borderless`.
    private func row(_ recipe: Recipe) -> some View {
        Button {
            if model.isSelecting {
                model.toggleSelection(of: recipe)
            } else {
                navigationPath.append(recipe)
            }
        } label: {
            HStack(spacing: 12) {
                if model.isSelecting {
                    Image(systemName: model.isSelected(recipe) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.isSelected(recipe) ? Color.accentColor : .secondary)
                        .imageScale(.large)
                }
                RecipeRowView(recipe: recipe) {
                    model.toggleFavorite(recipe)
                }
            }
            // A `Button` is hit-tested over its drawn content only, so without
            // this the row's padding and the gap left of the star are dead to
            // touch — a `NavigationLink` row was tappable across the whole cell.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Deleting and filing are single-recipe actions, and offering them while
        // the user is ticking a set to share reads as though they would apply to
        // the set. They come back when the mode ends.
        .swipeActions(edge: .trailing) {
            if !model.isSelecting {
                Button("Delete", role: .destructive) {
                    model.delete(recipe, context: modelContext)
                }
            }
        }
        .contextMenu {
            if !model.isSelecting {
                rowMenu(recipe)
            }
        }
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

    /// Entering the mode, and leaving it with or without sharing.
    ///
    /// Laid out to match the Inventory tab: the bulk action leading, Select and
    /// Done trailing. Two lists that both offer a selection mode should not put
    /// the way out of it in different corners.
    ///
    /// How many recipes are selected is shown in the navigation title rather
    /// than on the button, since a compact toolbar draws the button as its icon
    /// alone and any count in its label would never be seen.
    @ToolbarContentBuilder
    private func selectionToolbar() -> some ToolbarContent {
        if model.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Every selected recipe, not just the ones on screen. A
                    // collection chip tapped mid-selection changes what is
                    // displayed, and exporting only the survivors would send
                    // fewer recipes than the title says are selected.
                    model.exportSelection(from: recipes)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(model.exportButtonTitle)
                .disabled(!model.hasSelection)
            }
        }
        if !recipes.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isSelecting ? "Done" : "Select") {
                    if model.isSelecting {
                        model.endSelecting()
                    } else {
                        model.beginSelecting()
                    }
                }
            }
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
                .navigationTitle(model.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .warmNavigationTitle(model.navigationTitle)
                .warmBackground()
                .toolbar { selectionToolbar() }
                .sheet(item: $model.exportFile) { file in
                    ShareSheet(items: [file.url])
                }
                .alert(
                    "Couldn’t share",
                    isPresented: Binding(
                        get: { model.exportErrorMessage != nil },
                        set: { if !$0 { model.exportErrorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { model.exportErrorMessage = nil }
                } message: {
                    Text(model.exportErrorMessage ?? "")
                }
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
                //
                // Hidden while picking recipes to share, the same way it hides
                // in edit mode: the screen is doing one job, and a New Recipe
                // button in the corner is not part of it.
                if !model.isSelecting {
                    ExpandableFloatingActionButton(
                        primaryAction: { navigationPath.append(true) },
                        secondaryActions: RecipeImportAvailability.current.isAvailable
                            ? [FABAction(label: "Import Recipe", systemImage: "doc.text.viewfinder") { showingImport = true }]
                            : []
                    )
                }
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
