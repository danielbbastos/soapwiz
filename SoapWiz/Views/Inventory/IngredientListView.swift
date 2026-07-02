import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var model = IngredientListViewModel()
    @State private var selectedIngredient: Ingredient?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var displayedIngredients: [Ingredient] {
        model.filtered(ingredients)
    }

    private var selectedIngredients: [Ingredient] {
        ingredients.filter { model.selection.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                    // Edit mode owns the list selection (multi-select of model
                    // ids), so it needs its own List separate from the
                    // detail-driving single selection below.
                    List(selection: $model.selection) {
                        ingredientRows
                    }
                    .environment(\.editMode, $model.editMode)
                } else if horizontalSizeClass == .compact {
                    // Compact needs the selection binding: it is what makes
                    // the collapsed split view push the detail screen.
                    List(selection: $selectedIngredient) {
                        ingredientRows
                    }
                } else {
                    // Regular drives selection manually: a bound List draws
                    // the system's bordered-capsule indicator, which fights
                    // the row-background wash used as the selection style.
                    List {
                        tapToSelectIngredientRows
                    }
                }
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Inventory")
            .warmBackground()
            .searchable(text: $model.searchText, prompt: "Search ingredients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.editMode == .active {
                        Button("Delete", role: .destructive) {
                            model.deleteSelected(in: displayedIngredients, context: modelContext)
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
                SidebarToggleToolbarItem(columnVisibility: $columnVisibility, isActive: horizontalSizeClass == .regular)
            }
            .toolbar(removing: .sidebarToggle)
            .overlay(alignment: .bottomTrailing) {
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
        } detail: {
            Group {
                if let selectedIngredient {
                    NavigationStack {
                        IngredientDetailView(
                            ingredient: selectedIngredient,
                            autoAddPurchase: model.pendingIngredient?.persistentModelID == selectedIngredient.persistentModelID,
                            allowsTwoColumns: columnVisibility == .detailOnly
                        )
                        .id(selectedIngredient.persistentModelID)
                        .onAppear { model.pendingIngredient = nil }
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
                            "Select an Ingredient",
                            systemImage: "flask",
                            description: Text("Choose an ingredient from the list.")
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
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .alert(model.confirmingDelete.count == 1 ? "Delete Ingredient?" : "Delete Ingredients?", isPresented: Binding(
            get: { !model.confirmingDelete.isEmpty },
            set: { if !$0 { model.confirmingDelete = [] } }
        )) {
            Button("Delete", role: .destructive) { model.confirmDelete(context: modelContext) }
            Button("Cancel", role: .cancel) { model.confirmingDelete = [] }
        } message: {
            let purchaseCount = model.confirmingDelete.reduce(0) { $0 + $1.purchases.count }
            let ingredientWord = model.confirmingDelete.count == 1 ? "ingredient" : "ingredients"
            let purchaseWord = purchaseCount == 1 ? "purchase" : "purchases"
            Text("Deleting \(model.confirmingDelete.count) \(ingredientWord) will also delete \(purchaseCount) \(purchaseWord).")
        }
        .sheet(isPresented: $model.showingAddIngredient, onDismiss: {
            if let ingredient = model.pendingIngredient {
                selectedIngredient = ingredient
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

    private var ingredientRows: some View {
        ForEach(displayedIngredients) { ingredient in
            IngredientRowView(ingredient: ingredient)
                .tag(ingredient)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        model.delete(ingredient, context: modelContext)
                    }
                }
                .listRowBackground(Color.cardBackground)
        }
    }

    /// Regular-width rows: tapping selects, and the selected row is marked by
    /// an accent wash on its background instead of a system indicator.
    private var tapToSelectIngredientRows: some View {
        ForEach(displayedIngredients) { ingredient in
            Button {
                selectedIngredient = ingredient
            } label: {
                IngredientRowView(ingredient: ingredient)
                    // Make the whole row tappable, including the gap between
                    // the name and the trailing amount.
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    model.delete(ingredient, context: modelContext)
                }
            }
            .listRowBackground(
                selectedIngredient == ingredient
                    ? Color.accentColor.opacity(0.18)
                    : Color.cardBackground
            )
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
