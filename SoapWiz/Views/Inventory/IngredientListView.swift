import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Query(Ingredient.listDescriptor) private var ingredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query private var settingsRecords: [AppSettings]

    @State private var model = IngredientListViewModel()
    @State private var navigation = ListDetailNavigation<Ingredient>()
    /// The open ingredient's merge key, read when it opens: once a merge has
    /// deleted the row it can't be read off it. See `LiveIngredient`.
    @State private var selectedSlug = ""

    private var selectedIngredients: [Ingredient] {
        ingredients.filter { model.selection.contains($0.persistentModelID) }
    }

    /// Chips are drawn from the unfiltered inventory, not the displayed list:
    /// narrowing to one category must not make every other chip disappear.
    private var visibleCategories: [IngredientCategory] {
        model.visibleCategories(categories, in: ingredients)
    }

    private func row(_ ingredient: Ingredient, index: Int, count: Int) -> IngredientListRow {
        IngredientListRow(
            ingredient: ingredient,
            model: model,
            navigation: navigation,
            position: .position(index: index, count: count)
        )
    }

    /// Handles the open ingredient's row leaving the store without passing
    /// through this list. When a duplicate merge deleted it, the selection
    /// follows the surviving copy; otherwise it was deleted outright, on
    /// another device, and the detail closes rather than go on reading a
    /// deleted model.
    ///
    /// Unlike the other tabs, this can't just prune rows missing from the list:
    /// a merge removes the open row too, and closing the detail then would
    /// throw away whatever the user had open over it.
    ///
    /// The row counts as gone when SwiftData says so, or when the query no
    /// longer returns it (it includes hidden rows), since a delete synced from
    /// another device isn't certain to detach the instance. Both are needed:
    /// when this device's merge posts its notification, the query may not
    /// have caught up yet.
    ///
    /// `detailFollowed` is true only for that notification, which the open
    /// detail also answers by moving to the survivor itself.
    private func followRemovedSelection(detailFollowed: Bool) {
        guard let selection = navigation.selection,
              selection.modelContext == nil || selection.isDeleted || !ingredients.contains(selection)
        else { return }
        if let live = LiveIngredient.survivor(slug: selectedSlug, excluding: selection, in: modelContext) {
            navigation.followMerge(to: live, isHidden: live.isHidden, detailFollowed: detailFollowed)
        } else {
            navigation.reset()
        }
    }

    var body: some View {
        // Worked out once per pass, in one walk over the inventory: it sums each
        // row's stock, and several places below need the result. Favourites can't
        // be part of the `@Query` sort (`SortDescriptor` has no `Bool` overload),
        // so the pinning is applied there, after filtering.
        let content = model.content(for: ingredients)
        let displayed = content.displayed
        ListDetailContainer(
            navigation: navigation,
            placeholder: "Select an Ingredient",
            placeholderSymbol: "flask",
            placeholderDescription: "Choose an ingredient from the list to see its purchases here.",
            hasItems: !displayed.isEmpty
        ) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if ingredients.isEmpty {
                        HoneyLedgerEmptyState(
                            "No ingredients yet",
                            systemImage: "flask",
                            description: "Tap + to add one."
                        )
                    } else if displayed.isEmpty {
                        if !model.searchText.isEmpty {
                            ContentUnavailableView.search(text: model.searchText)
                        } else {
                            HoneyLedgerEmptyState(
                                "No ingredients match",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: "Change or clear the filters."
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
                            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, ingredient in
                                row(ingredient, index: index, count: displayed.count)
                            }
                        }
                        .environment(\.editMode, $model.editMode)
                    } else {
                        List {
                            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, ingredient in
                                row(ingredient, index: index, count: displayed.count)
                            }
                        }
                        .environment(\.editMode, $model.editMode)
                        // The chips already stand off the list on their own; the
                        // scroll view's default top margin on top of that left
                        // the two looking unrelated.
                        .contentMargins(.top, visibleCategories.isEmpty ? nil : 0, for: .scrollContent)
                    }
                }
                .readableWidth()
                .navigationTitle("Inventory")
                .navigationBarTitleDisplayMode(.large)
                .ledgerLargeTitle(subtitle: model.editMode == .inactive ? content.summary.line : nil)
                .ledgerBackground(sunken: navigation.isWide)
                .navigationDestination(for: Ingredient.self) { IngredientDetailView(ingredient: $0) }
                // The chips are hidden while selecting: they would compete with
                // the selection the toolbar is there to act on.
                .headerStrip(showsList: !displayed.isEmpty) {
                    VStack(spacing: 0) {
                        // Nothing to search with an empty inventory.
                        if !ingredients.isEmpty {
                            SearchField("Search ingredients", text: $model.searchText)
                                .padding(.bottom, 12)
                        }
                        if !visibleCategories.isEmpty && model.editMode == .inactive {
                            InventoryCategoryFilterBar(
                                categories: visibleCategories,
                                model: model,
                                counts: content.categoryCounts
                            )
                        }
                    }
                }
                .onChange(of: categories) { _, updated in
                    model.pruneSelectedCategories(against: updated)
                }
                .onChange(of: AppSettings.tracksInventory(from: settingsRecords), initial: true) { _, tracks in
                    model.tracksInventory = tracks
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.editMode == .active {
                            // "Remove" rather than "Delete": a selection can hold
                            // library rows, which are hidden rather than deleted.
                            Button("Remove", role: .destructive) {
                                model.deleteSelected(in: displayed)
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
                        ],
                        besideTabBar: navigation.fabBesideTabBar
                    )
                } else if !model.selection.isEmpty {
                    createRecipeButton
                }
            }
        } detail: { IngredientDetailView(ingredient: $0) }
        // A hidden row has left the list, and its detail staying open beside
        // the list would outlive it.
        .onChange(of: ingredients.filter(\.isHidden)) { _, hidden in
            navigation.close(ifShowingAnyOf: hidden)
        }
        .onChange(of: navigation.selection) { _, selection in
            selectedSlug = selection?.librarySlug ?? ""
        }
        // Deletions made in this list close the detail before they happen.
        // These catch the rest: a merge, and a delete synced from another device.
        .onChange(of: ingredients) {
            followRemovedSelection(detailFollowed: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
            followRemovedSelection(detailFollowed: true)
        }
        .alert(model.removalConfirmationTitle, isPresented: Binding(
            get: { model.isConfirmingRemoval },
            set: { if !$0 { model.cancelRemoval() } }
        )) {
            // Only destructive when something is actually deleted: a confirmation
            // that nothing but hides rows shouldn't wear red.
            Button(
                model.confirmingDelete.isEmpty ? "Hide" : "Delete",
                role: model.confirmingDelete.isEmpty ? nil : .destructive
            ) {
                navigation.close(ifShowingAnyOf: model.confirmingDelete + model.confirmingHide)
                model.confirmDelete(context: modelContext)
            }
            Button("Cancel", role: .cancel) { model.cancelRemoval() }
        } message: {
            Text(model.removalConfirmationMessage)
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
        // A new ingredient opens on its detail, with Add Purchase up over it
        // when stock is tracked.
        .sheet(isPresented: $model.showingAddIngredient, onDismiss: {
            guard let ingredient = model.pendingIngredient else { return }
            model.pendingIngredient = nil
            navigation.show(ingredient)
            if model.tracksInventory {
                nav.detailSheetRequest = .addPurchase(ingredient)
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
                .foregroundStyle(Color.ink)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.paperRaised, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.ruleStrong, lineWidth: 1))
                .shadow(color: Color.shadow.opacity(0.18), radius: 10, y: 4)
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
                        .foregroundStyle(Color.onAmber)
                        .padding(2)
                        .background(Color.amber, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .foregroundStyle(model.hasActiveFilters ? Color.amberText : Color.ink)
    }
}
