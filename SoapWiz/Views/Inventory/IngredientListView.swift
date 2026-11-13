import SwiftUI
import SwiftData

struct IngredientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var nav
    @Environment(InventoryRows.self) var rows
    @Environment(SettingsState.self) private var settings
    @Environment(\.isTourSandbox) private var isTourSandbox
    @Environment(TourLauncher.self) private var tourLauncher
    @AppStorage(FirstOwnedCelebration.defaultsKey) private var celebratedFirstOwned = false
    @State private var celebrationTick = 0

    @State var model = IngredientListViewModel()
    /// The open ingredient's merge key, read when it opens: once a merge has
    /// deleted the row it can't be read off it. See `LiveIngredient`.
    @State private var selectedSlug = ""
    /// The browse list's height, which sizes the empty-state row to sit in the
    /// middle of what is visible without making the list scroll.
    @State private var listHeight: CGFloat = 0

    /// Held by `AppNavigation` rather than here, so the onboarding tour can open
    /// an ingredient from outside.
    private var navigation: ListDetailNavigation<Ingredient> { nav.inventory }

    private var selectedIngredients: [Ingredient] {
        rows.ingredients.filter { model.selection.contains($0.persistentModelID) }
    }

    private func row(_ ingredient: Ingredient, stockLevels: StockLevels, index: Int, count: Int) -> IngredientListRow {
        IngredientListRow(
            ingredient: ingredient,
            model: model,
            stock: stockLevels.stock(for: ingredient),
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
    /// The row counts as gone when SwiftData says so, or when the rows no
    /// longer include it (they include hidden rows), since a delete synced from
    /// another device isn't certain to detach the instance. Both are needed:
    /// when this device's merge posts its notification, the rows may not
    /// have caught up yet, which is why that handler refreshes them first.
    ///
    /// `detailFollowed` is true only for that notification, which the open
    /// detail also answers by moving to the survivor itself.
    private func followRemovedSelection(detailFollowed: Bool) {
        guard let selection = navigation.selection,
              selection.modelContext == nil || selection.isDeleted || !rows.ingredients.contains(selection)
        else { return }
        if let live = LiveIngredient.survivor(slug: selectedSlug, excluding: selection, in: modelContext) {
            navigation.followMerge(to: live, isHidden: live.isHidden, detailFollowed: detailFollowed)
        } else {
            navigation.reset()
        }
    }

    /// The list in Select mode. Library matches are selectable too, so a search
    /// that only finds library rows doesn't leave it empty.
    private func selectList(
        displayed: [Ingredient],
        libraryMatches: [Ingredient],
        stockLevels: StockLevels
    ) -> some View {
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
            ingredientRows(displayed: displayed, libraryMatches: libraryMatches, stockLevels: stockLevels)
        }
        .environment(\.editMode, $model.editMode)
    }

    /// The owned rows, then the library rows a search turned up under their own
    /// header. Shared by both lists so they can't drift apart.
    @ViewBuilder
    private func ingredientRows(
        displayed: [Ingredient],
        libraryMatches: [Ingredient],
        stockLevels: StockLevels
    ) -> some View {
        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, ingredient in
            row(ingredient, stockLevels: stockLevels, index: index, count: displayed.count)
        }
        if !libraryMatches.isEmpty {
            Section {
                ForEach(Array(libraryMatches.enumerated()), id: \.element.id) { index, ingredient in
                    row(ingredient, stockLevels: stockLevels, index: index, count: libraryMatches.count)
                }
            } header: {
                HoneyLedgerSectionLabel("From the library")
            }
        }
    }

    /// The list outside Select mode: the owned matches, then the library rows a
    /// search turned up that the user doesn't own yet.
    private func browseList(
        displayed: [Ingredient],
        libraryMatches: [Ingredient],
        stockLevels: StockLevels,
        hasChips: Bool,
        emptyState: InventoryEmptyState?
    ) -> some View {
        // The empty states are a row of this list rather than a view that
        // replaces it: swapping the scroll view out leaves the UIKit large
        // title laid out against one that is gone.
        List {
            if let notice = rows.syncNotice {
                Section {
                    InventorySyncStatusRow(notice: notice)
                        .ledgerSheetRow(position: .only)
                }
                .listSectionSpacing(.custom(16))
                .transition(.opacity)
            }
            if let emptyState {
                emptyState.listEmptyStateRow(listHeight: listHeight)
            }
            ingredientRows(displayed: displayed, libraryMatches: libraryMatches, stockLevels: stockLevels)
        }
        .measuringListHeight($listHeight)
        .animation(.default, value: rows.syncNotice)
        .environment(\.editMode, $model.editMode)
        // The chips already stand off the list on their own; the
        // scroll view's default top margin on top of that left
        // the two looking unrelated.
        .contentMargins(.top, hasChips ? 0 : nil, for: .scrollContent)
    }

    /// Records the first owned ingredient and asks for the haptic by bumping
    /// `celebrationTick`, in one place so the flag can't pre-empt the haptic.
    /// Never in the tour's sandbox, which must neither buzz nor use up the flag.
    private func celebrateFirstOwned(from old: Int, to new: Int) {
        guard FirstOwnedCelebration.shouldPlay(
            old: old,
            new: new,
            tracksInventory: model.tracksInventory,
            alreadyCelebrated: celebratedFirstOwned || isTourSandbox
        ) else { return }
        celebratedFirstOwned = true
        celebrationTick += 1
    }

    var body: some View {
        // Worked out once per pass, in one walk over the inventory: it sums each
        // row's stock, and several places below need the result. Favourites can't
        // be part of the fetch's sort (`SortDescriptor` has no `Bool` overload),
        // so the pinning is applied there, after filtering.
        let ingredients = rows.ingredients
        let stockLevels = StockLevels(rows.purchases)
        let content = model.content(for: ingredients, stock: stockLevels, purchases: rows.purchases)
        let displayed = content.displayed
        let libraryMatches = content.libraryMatches
        let hasListedIngredients = ingredients.contains { !$0.isHidden }
        let visibleCategories = categoryChips(stock: stockLevels)
        let hasChips = !visibleCategories.isEmpty || model.effectiveAttentionFilter != nil
        let listHasItems = !displayed.isEmpty || !libraryMatches.isEmpty
        let ownedTrigger: Int = hasListedIngredients ? content.ownedCount : -1
        ListDetailContainer(
            navigation: navigation,
            placeholder: "Select an Ingredient",
            placeholderSymbol: "flask",
            placeholderDescription: "Choose an ingredient from the list to see its purchases here.",
            hasItems: listHasItems
        ) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if listHasItems && model.editMode == .active {
                        selectList(displayed: displayed, libraryMatches: libraryMatches, stockLevels: stockLevels)
                    } else {
                        browseList(
                            displayed: displayed,
                            libraryMatches: libraryMatches,
                            stockLevels: stockLevels,
                            hasChips: hasChips,
                            emptyState: listHasItems ? nil : InventoryEmptyState(
                                model: model,
                                hasListedIngredients: hasListedIngredients,
                                inScopeTotal: content.summary.total
                            )
                        )
                    }
                }
                .readableWidth()
                .navigationTitle("Inventory")
                .navigationBarTitleDisplayMode(.large)
                .ledgerLargeTitle(subtitle: model.editMode == .inactive ? content.summary.line : nil)
                .ledgerBackground(sunken: navigation.isWide)
                .inventoryDestinations()
                // The chips are hidden while selecting: they would compete with
                // the selection the toolbar is there to act on.
                .headerStrip {
                    headerContent(
                        showsSearch: hasListedIngredients,
                        categories: visibleCategories,
                        hasChips: hasChips,
                        counts: content.categoryCounts
                    )
                }
                .onChange(of: rows.categories) { _, updated in
                    model.pruneSelectedCategories(against: updated)
                }
                .onChange(of: settings.tracksInventory, initial: true) { _, tracks in
                    model.tracksInventory = tracks
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.editMode == .active {
                            // "Remove" rather than "Delete": a selection can hold
                            // library rows, which are hidden rather than deleted.
                            Button("Remove", role: .destructive) {
                                model.deleteSelected(in: displayed + libraryMatches)
                            }
                            .disabled(model.selection.isEmpty)
                        } else {
                            InventoryFilterButton(model: model)
                        }
                    }
                    if model.editMode == .inactive && model.tracksInventory {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShoppingListToolbarButton(isPresented: $model.showingShoppingList)
                        }
                    }
                    if listHasItems || model.editMode == .active {
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
                        primaryLabel: "Add ingredient",
                        primarySystemImage: "flask",
                        primaryAction: { model.showingAddIngredient = true },
                        secondaryActions: secondaryActions,
                        besideTabBar: navigation.fabBesideTabBar,
                        tourAnchor: .inventoryAddButton
                    )
                } else if !model.selection.isEmpty {
                    InventoryCreateRecipeButton(model: model, selected: selectedIngredients)
                }
            }
        } detail: { IngredientDetailView(ingredient: $0).purchaseDestinations().batchAndRecipeDestinations() }
        // The first ingredient is the one that makes Inventory feel like the
        // user's own. A trigger of -1 while no rows are loaded keeps the rows
        // arriving at launch from reading as a first purchase.
        .sensoryFeedback(.success, trigger: celebrationTick)
        .onChange(of: ownedTrigger, celebrateFirstOwned)
        // Home's first-run screen asking for the spreadsheet import. `initial`
        // covers this tab being built after the request is set.
        .onChange(of: nav.pendingInventoryImport, initial: true) { startPendingImport() }
        // Home's Needs attention card asking for a filtered list.
        .onChange(of: nav.pendingInventoryFilter, initial: true) { startPendingFilter() }
        .onChange(of: nav.detailSheetClosings) { startPendingImport() }
        .onChange(of: nav.recipeFormClosings) { startPendingImport() }
        .onChange(of: tourLauncher.isCoverOnScreen) { startPendingImport() }
        // A hidden row has left the list, and its detail staying open beside
        // the list would outlive it.
        .onChange(of: ingredients.filter(\.isHidden)) { _, hidden in
            navigation.close(ifShowingAnyOf: hidden)
        }
        // `initial`, since the selection lives on `AppNavigation` and can
        // already be set when this view is built, which a change never reports.
        .onChange(of: navigation.selection, initial: true) { _, selection in
            selectedSlug = selection?.librarySlug ?? ""
        }
        // Deletions made in this list close the detail before they happen.
        // These catch the rest: a merge, and a delete synced from another device.
        .onChange(of: ingredients) {
            followRemovedSelection(detailFollowed: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
            rows.refresh()
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
        .sheet(isPresented: $model.showingCSVImport) {
            CSVImportFlowView()
        }
        .sheet(isPresented: $model.showingFilters) {
            InventoryFilterView(model: model)
        }
        .shoppingListSheet(
            isPresented: $model.showingShoppingList,
            ingredients: rows.ingredients,
            purchases: rows.purchases,
            tracksInventory: settings.tracksInventory
        )
    }

    private func startPendingFilter() {
        guard let filter = nav.takePendingInventoryFilter() else { return }
        if model.editMode == .active {
            model.editMode = .inactive
            model.selection.removeAll()
        }
        navigation.reset()
        model.applyAttentionFilter(filter)
    }

    private func startPendingImport() {
        guard nav.takePendingInventoryImport(tourCoverOnScreen: tourLauncher.isCoverOnScreen) != nil else { return }
        model.showingCSVImport = true
    }

    private var secondaryActions: [FABAction] {
        var actions: [FABAction] = []
        if !rows.ingredients.isEmpty {
            actions.append(FABAction(label: "Bulk import purchases", systemImage: "shippingbox") {
                model.showingBulkImport = true
            })
        }
        actions.append(FABAction(label: "Import from spreadsheet", systemImage: "tablecells") {
            model.showingCSVImport = true
        })
        return actions
    }
}
