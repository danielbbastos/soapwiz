import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var model = IngredientListViewModel()
    @State private var navigationPath = NavigationPath()

    private var displayedIngredients: [Ingredient] {
        model.filtered(ingredients)
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
                    } else {
                        List(selection: $model.selection) {
                            ForEach(displayedIngredients) { ingredient in
                                NavigationLink(value: ingredient) {
                                    IngredientRowView(ingredient: ingredient)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        model.delete(ingredient, context: modelContext)
                                    }
                                }
                            }
                        }
                        .environment(\.editMode, $model.editMode)
                    }
                }
                .navigationTitle("Inventory")
                .navigationDestination(for: Ingredient.self) { ingredient in
                    IngredientDetailView(
                        ingredient: ingredient,
                        autoAddPurchase: model.pendingIngredient?.persistentModelID == ingredient.persistentModelID
                    )
                    .onAppear { model.pendingIngredient = nil }
                }
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
                navigationPath.append(ingredient)
            }
        }) {
            IngredientFormView(onSave: { ingredient in
                model.pendingIngredient = ingredient
            })
        }
        .sheet(isPresented: $model.showingFilters) {
            InventoryFilterView(model: model)
        }
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
                        .background(.blue, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .foregroundStyle(model.hasActiveFilters ? .blue : .primary)
    }
}
