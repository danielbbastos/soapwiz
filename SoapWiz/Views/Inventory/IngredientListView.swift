import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]

    @State private var model = IngredientListViewModel()
    @State private var navigationPath = NavigationPath()

    // Favourites can't be part of the `@Query` sort: `SortDescriptor` has no `Bool`
    // overload, so the pinning is applied here, after filtering.
    private var displayedIngredients: [Ingredient] {
        model.filtered(ingredients).favoritesFirst
    }

    private var selectedIngredients: [Ingredient] {
        ingredients.filter { model.selection.contains($0.persistentModelID) }
    }

    /// A `Button` rather than a `NavigationLink`, purely to drop the disclosure
    /// chevron: a link used as a row's root always draws one and there is no
    /// modifier to suppress it. The push is the same, just issued by hand. This
    /// is what the recipe list already does.
    ///
    /// While selecting, the row is its bare content instead: the list is then
    /// handling taps itself to build the selection, and a button in the way
    /// would take them.
    @ViewBuilder
    private func row(_ ingredient: Ingredient) -> some View {
        let content = IngredientRowView(ingredient: ingredient) {
            model.toggleFavorite(ingredient)
        }
        if model.editMode == .active {
            content
                .listRowBackground(Color.cardBackground)
        } else {
            Button {
                navigationPath.append(ingredient)
            } label: {
                // A `Button` is hit-tested over its drawn content only, so
                // without this the row's padding and the gap left of the star
                // are dead to touch — a `NavigationLink` row was tappable
                // across the whole cell.
                content
                    .contentShape(Rectangle())
            }
            // Keeps the row from taking on button tinting; the star inside stays
            // tappable because it is `.borderless`.
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    model.delete(ingredient)
                }
            }
            .listRowBackground(Color.cardBackground)
        }
    }

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
                    } else if displayedIngredients.isEmpty {
                        if !model.searchText.isEmpty {
                            ContentUnavailableView.search(text: model.searchText)
                        } else {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try adjusting your filters.")
                            )
                        }
                    } else if model.editMode == .active {
                        // The selection binding is attached only while selecting,
                        // because on iPad it is live outside edit mode too: a
                        // plain tap marks the row selected on the way into the
                        // detail screen, and the row comes back drawn in the
                        // selected style — white label text, over the row
                        // background this app supplies itself, which hides the
                        // tinted fill that white is meant to be read against.
                        // The row then looks empty until something forces a
                        // redraw, and empty again as soon as that goes away.
                        //
                        // Nothing outside edit mode reads `selection`: it exists
                        // for the bulk delete, which only Select mode offers.
                        List(selection: $model.selection) {
                            ForEach(displayedIngredients) { row($0) }
                        }
                        .environment(\.editMode, $model.editMode)
                    } else {
                        List {
                            ForEach(displayedIngredients) { row($0) }
                        }
                        .environment(\.editMode, $model.editMode)
                    }
                }
                .navigationTitle("Inventory")
                .navigationBarTitleDisplayMode(.inline)
                .warmNavigationTitle("Inventory")
                .warmBackground()
                .navigationDestination(for: Ingredient.self) { ingredient in
                    IngredientDetailView(
                        ingredient: ingredient,
                        autoAddPurchase: model.pendingIngredient?.persistentModelID == ingredient.persistentModelID
                    )
                    .onAppear { model.pendingIngredient = nil }
                }
                .searchable(text: $model.searchText, prompt: "Search ingredients")
                .onChange(of: categories) { _, updated in
                    model.pruneSelectedCategories(against: updated)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.editMode == .active {
                            Button("Delete", role: .destructive) {
                                model.deleteSelected(in: displayedIngredients)
                            }
                            .disabled(model.selection.isEmpty)
                        } else {
                            filterButton
                        }
                    }
                    if !ingredients.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(model.editMode == .active ? "Done" : "Select") {
                                withAnimation {
                                    model.editMode = model.editMode == .active ? .inactive : .active
                                }
                                if model.editMode == .inactive { model.selection.removeAll() }
                            }
                        }
                    }
                }

                if model.editMode == .inactive {
                    ExpandableFloatingActionButton(
                        primaryAction: { model.showingAddIngredient = true },
                        secondaryActions: ingredients.isEmpty ? [] : [
                            FABAction(label: "Bulk Import", systemImage: "shippingbox") {
                                model.showingBulkImport = true
                            }
                        ]
                    )
                } else if !model.selection.isEmpty {
                    createRecipeButton
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
            Text(model.deleteConfirmationMessage)
        }
        .alert(
            model.deleteBlockedIngredients.count == 1 ? "Cannot Delete Ingredient" : "Cannot Delete Ingredients",
            isPresented: Binding(
                get: { !model.deleteBlockedIngredients.isEmpty },
                set: { if !$0 { model.deleteBlockedIngredients = [] } }
            )
        ) {
            Button("OK", role: .cancel) { model.deleteBlockedIngredients = [] }
        } message: {
            Text(model.deleteBlockedMessage)
        }
        .sheet(isPresented: $model.showingAddIngredient, onDismiss: {
            if let ingredient = model.pendingIngredient {
                navigationPath.append(ingredient)
            }
        }, content: {
            IngredientFormView(onSave: { ingredient in
                model.pendingIngredient = ingredient
            })
        })
        .sheet(isPresented: $model.showingBulkImport) {
            BulkImportView()
        }
        .sheet(isPresented: $model.showingFilters) {
            InventoryFilterView(model: model)
        }
    }

    /// Shown while in select mode, floating above the tab bar (a `.bottomBar`
    /// toolbar item would sit behind the TabView's tab bar).
    private var createRecipeButton: some View {
        Button {
            let ingredients = selectedIngredients
            model.editMode = .inactive
            model.selection.removeAll()
            nav.createRecipe(with: ingredients)
        } label: {
            Text("Create recipe with… (\(model.selection.count))")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.cardBackground, in: .capsule)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var filterButton: some View {
        Button {
            model.showingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: model.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                if model.hasActiveFilters {
                    Text("\(model.activeFilterCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .foregroundStyle(model.hasActiveFilters ? Color.accentColor : .primary)
    }
}
