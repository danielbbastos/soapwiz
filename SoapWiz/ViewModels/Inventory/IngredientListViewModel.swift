import Foundation
import SwiftData
import SwiftUI

enum StockStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case inStock = "In Stock"
    case lowStock = "Low Stock"
    case outOfStock = "Out of Stock"

    var id: Self { self }
}

enum ExpiryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case expiringSoon = "Expiring Soon"
    case expired = "Expired"
    case noExpiry = "No Expiry Set"

    var id: Self { self }
}

@MainActor
@Observable
final class IngredientListViewModel {
    var showingAddIngredient: Bool = false
    var showingBulkImport: Bool = false
    var showingFilters: Bool = false
    var pendingIngredient: Ingredient?
    var editMode: EditMode = .inactive
    var selection: Set<PersistentIdentifier> = []
    var confirmingDelete: [Ingredient] = []

    /// Library rows staged for hiding by the same confirmation that deletes the
    /// user-created ones beside them. A bulk selection can hold both kinds, and
    /// one Remove has to do the right thing to each.
    var confirmingHide: [Ingredient] = []

    var deleteBlockedIngredients: [Ingredient] = []

    var searchText: String = ""
    var selectedCategories: Set<PersistentIdentifier> = []
    var stockStatus: StockStatusFilter = .all
    var selectedUnits: Set<IngredientUnit> = []
    var expiryFilter: ExpiryFilter = .all

    /// Mirrors `AppSettings.tracksInventory`. Off, the stock and expiry filters
    /// are ignored rather than cleared: their menus are hidden, and a filter set
    /// before tracking was switched off must not silently empty the list, yet
    /// it comes back as it was when tracking is switched on again.
    var tracksInventory: Bool = true

    var hasActiveFilters: Bool { activeFilterCount > 0 }

    var activeFilterCount: Int {
        (selectedCategories.isEmpty ? 0 : 1) +
        (effectiveStockStatus == .all ? 0 : 1) +
        (selectedUnits.isEmpty ? 0 : 1) +
        (effectiveExpiryFilter == .all ? 0 : 1)
    }

    private var effectiveStockStatus: StockStatusFilter { tracksInventory ? stockStatus : .all }
    private var effectiveExpiryFilter: ExpiryFilter { tracksInventory ? expiryFilter : .all }

    /// Drops selections whose category no longer exists. `DuplicateMerger` deletes
    /// the losing row of a duplicate pair, and a filter still holding its ID would
    /// silently match nothing and show an empty inventory.
    func pruneSelectedCategories(against categories: [IngredientCategory]) {
        guard !selectedCategories.isEmpty else { return }
        selectedCategories.formIntersection(categories.map(\.persistentModelID))
    }

    func clearFilters() {
        selectedCategories = []
        stockStatus = .all
        selectedUnits = []
        expiryFilter = .all
    }

    /// An empty selection already means every category, so this doubles as the
    /// selected state of the chip row's leading "All" chip.
    var isShowingAllCategories: Bool { selectedCategories.isEmpty }

    func toggleCategory(_ category: IngredientCategory) {
        let id = category.persistentModelID
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }

    func selectAllCategories() {
        selectedCategories.removeAll()
    }

    /// Categories worth a chip: those holding at least one of `ingredients`,
    /// plus any already selected. A fresh install seeds all seven, and a chip
    /// for an empty category only ever leads to "No Results" — but one that
    /// empties *while* it is the active filter has to stay, or the row would
    /// reshuffle under the tap that just set it.
    ///
    /// The in-use set comes from the ingredients actually being listed rather
    /// than from `category.ingredients`, so the chips keep matching the list
    /// once SW-137 starts holding library rows back from it.
    func visibleCategories(
        _ categories: [IngredientCategory],
        in ingredients: [Ingredient]
    ) -> [IngredientCategory] {
        // Hidden rows are discounted here rather than at the call site, which passes
        // the unfiltered inventory: a category holding nothing but hidden rows would
        // otherwise keep a chip that leads only to "No Results".
        let inUse = Set(ingredients.filter { !$0.isHidden }.compactMap { $0.category?.persistentModelID })
        return categories.filter { category in
            let id = category.persistentModelID
            return inUse.contains(id) || selectedCategories.contains(id)
        }
    }

    /// The hidden rows, for the unhide screen.
    ///
    /// Hiding filters here rather than in the view's `@Query` so the rows stay in the
    /// store: a recipe already built on one keeps working, and its batches still
    /// deduct from it. What hiding takes away is the row's place in Inventory and in
    /// the pickers — not the row.
    func hidden(_ ingredients: [Ingredient]) -> [Ingredient] {
        ingredients.filter(\.isHidden)
    }

    func filtered(_ ingredients: [Ingredient]) -> [Ingredient] {
        ingredients.filter { ingredient in
            guard !ingredient.isHidden else { return false }

            let matchesSearch = searchText.isEmpty ||
                ingredient.name.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategories.isEmpty ||
                (ingredient.category.map { selectedCategories.contains($0.persistentModelID) } ?? false)

            let matchesStock: Bool
            switch effectiveStockStatus {
            case .all:        matchesStock = true
            case .inStock:    matchesStock = ingredient.totalRemaining > 0 && !ingredient.isLowStock
            case .lowStock:   matchesStock = ingredient.isLowStock && ingredient.totalRemaining > 0
            case .outOfStock: matchesStock = ingredient.totalRemaining == 0
            }

            let matchesUnit = selectedUnits.isEmpty ||
                selectedUnits.contains(where: { $0.rawValue == ingredient.unit })

            let matchesExpiry: Bool
            switch effectiveExpiryFilter {
            case .all:           matchesExpiry = true
            case .expiringSoon:  matchesExpiry = ingredient.nearestUpcomingExpiry != nil
            case .expired:       matchesExpiry = ingredient.hasExpiredPurchase
            case .noExpiry:      matchesExpiry = ingredient.purchases.allSatisfy { $0.expiryDate == nil }
            }

            return matchesSearch && matchesCategory && matchesStock && matchesUnit && matchesExpiry
        }
    }

    /// Animated so the row's move to or from the pinned group reads as a move
    /// rather than a jump.
    func toggleFavorite(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isFavorite.toggle()
        }
    }

    /// Hiding is immediate and needs no confirmation: nothing is lost, the row keeps
    /// its purchases, recipes already built on it are untouched, and Unhide is one tap
    /// away in the filter sheet.
    func hide(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isHidden = true
        }
    }

    func unhide(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isHidden = false
        }
    }

    /// A library row is hidden rather than deleted, and recipe usage doesn't stand in
    /// the way: hiding leaves the ingredient in place for every recipe already
    /// pointing at it.
    ///
    /// For a user-created row, being used by a recipe blocks deletion outright and
    /// takes precedence over the remaining-stock confirmation: losing stock is
    /// recoverable, silently gutting a recipe's oil percentages — and with them its
    /// lye calculation — is not.
    ///
    /// Everything else routes through `confirmingDelete`. An ingredient carries sap
    /// values, density and a fatty-acid profile that are tedious to re-enter, and
    /// there is no undo, so no deletion happens on a single tap.
    func delete(_ ingredient: Ingredient) {
        guard !ingredient.isLibraryInstalled else {
            hide(ingredient)
            return
        }
        if ingredient.isUsedInRecipes {
            deleteBlockedIngredients = [ingredient]
        } else {
            confirmingDelete = [ingredient]
        }
    }

    /// If any selected user-created ingredient is used by a recipe, nothing happens at
    /// all — a partial removal would be harder to reason about than none. Library rows
    /// in the same selection are staged for hiding, which no recipe can block.
    func deleteSelected(in ingredients: [Ingredient]) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        guard !targets.isEmpty else { return }
        let deletable = targets.filter { !$0.isLibraryInstalled }
        let blocked = deletable.filter(\.isUsedInRecipes)
        if !blocked.isEmpty {
            deleteBlockedIngredients = blocked
        } else {
            confirmingHide = targets.filter(\.isLibraryInstalled)
            confirmingDelete = deletable
        }
    }

    var isConfirmingRemoval: Bool { !confirmingDelete.isEmpty || !confirmingHide.isEmpty }

    func cancelRemoval() {
        confirmingDelete = []
        confirmingHide = []
    }

    /// Titles the confirmation for what it will actually do, which depends on the mix:
    /// a selection can be all library rows, all user-created ones, or both.
    var removalConfirmationTitle: String {
        if confirmingHide.isEmpty {
            return confirmingDelete.count == 1 ? "Delete Ingredient?" : "Delete Ingredients?"
        }
        if confirmingDelete.isEmpty {
            return confirmingHide.count == 1 ? "Hide Ingredient?" : "Hide Ingredients?"
        }
        return "Remove Ingredients?"
    }

    /// Spells the hide out whenever library rows are involved. "Delete" is the word
    /// the user reached for, and being told that some rows are only hidden — and where
    /// to find them again — is the whole point of the confirmation.
    var removalConfirmationMessage: String {
        guard !confirmingHide.isEmpty else { return deleteConfirmationMessage }

        let hidePart: String
        if confirmingHide.count == 1, let name = confirmingHide.first?.name {
            hidePart = "\"\(name)\" is a library ingredient, so it will be hidden rather than deleted. "
                + "You can bring it back from Filters."
        } else {
            hidePart = "\(confirmingHide.count) library ingredients will be hidden rather than deleted. "
                + "You can bring them back from Filters."
        }

        guard !confirmingDelete.isEmpty else { return hidePart }
        return hidePart + "\n\n" + deleteConfirmationMessage
    }

    /// Explains which recipes are in the way, so the user knows where to go next.
    var deleteBlockedMessage: String {
        guard !deleteBlockedIngredients.isEmpty else { return "" }

        if deleteBlockedIngredients.count == 1, let ingredient = deleteBlockedIngredients.first {
            let recipes = ingredient.recipesUsingThis.map(\.name).sorted()
            let target = recipes.count == 1 ? "that recipe" : "those recipes"
            return "\"\(ingredient.name)\" is used in \(recipes.abbreviatedList()). "
                + "Remove it from \(target) first."
        }

        let names = deleteBlockedIngredients.map(\.name).sorted()
        return "\(names.abbreviatedList()) are used in recipes. Remove them from those recipes first."
    }

    /// Message for the delete confirmation. Lives here rather than in the view so the
    /// wording is testable.
    var deleteConfirmationMessage: String {
        guard !confirmingDelete.isEmpty else { return "" }

        let purchaseCount = confirmingDelete.reduce(0) { $0 + $1.purchases.count }
        guard purchaseCount > 0 else {
            if confirmingDelete.count == 1, let name = confirmingDelete.first?.name {
                return "Delete \"\(name)\"? This can't be undone."
            }
            return "Delete \(confirmingDelete.count) ingredients? This can't be undone."
        }

        let ingredientWord = confirmingDelete.count == 1 ? "ingredient" : "ingredients"
        let purchaseWord = purchaseCount == 1 ? "purchase" : "purchases"
        return "Deleting \(confirmingDelete.count) \(ingredientWord) will also delete "
            + "\(purchaseCount) \(purchaseWord). This can't be undone."
    }

    /// Applies both halves of the staged removal: library rows are hidden, the rest
    /// deleted.
    func confirmDelete(context: ModelContext) {
        confirmingHide.forEach { $0.isHidden = true }
        confirmingDelete.forEach { $0.deleteWithOwnedRows(in: context) }
        confirmingHide = []
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
