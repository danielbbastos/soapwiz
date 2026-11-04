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

enum LibraryScope: String, CaseIterable, Identifiable {
    case owned = "My Ingredients"
    case all = "Whole Library"

    var id: Self { self }
}

/// The "N ingredients · L low · O out" line under the Inventory title.
struct InventoryCountSummary: Equatable {
    let total: Int
    /// Low, and not yet out.
    let low: Int
    let out: Int

    /// Nil when there is nothing to count, so the line is left out.
    var line: String? {
        guard total > 0 else { return nil }
        // Plain `String(localized:)` leaves the agreement markup as it is: only
        // an attributed string resolves it.
        var parts = [String(AttributedString(localized: "^[\(total) ingredient](inflect: true)").characters)]
        if low > 0 { parts.append(String(localized: "\(low) low")) }
        if out > 0 { parts.append(String(localized: "\(out) out")) }
        return parts.joined(separator: " · ")
    }
}

/// What the Inventory screen draws from the store, computed together by
/// `IngredientListViewModel.content(for:stock:)`.
struct IngredientListContent {
    let displayed: [Ingredient]
    let categoryCounts: (all: Int, byCategory: [PersistentIdentifier: Int])
    let summary: InventoryCountSummary

    /// Library rows the user doesn't own that match the search, shown below the
    /// owned matches. Only filled while searching with the scope on My Ingredients.
    let libraryMatches: [Ingredient]

    /// Listed (non-hidden) ingredients the user owns, whatever the scope.
    let ownedCount: Int
}

@MainActor
@Observable
final class IngredientListViewModel {
    var showingAddIngredient: Bool = false
    var showingBulkImport: Bool = false
    var showingCSVImport: Bool = false
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
    var libraryScope: LibraryScope = .owned

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
        (effectiveExpiryFilter == .all ? 0 : 1) +
        (effectiveLibraryScope == .all && tracksInventory ? 1 : 0)
    }

    private var effectiveStockStatus: StockStatusFilter { tracksInventory ? stockStatus : .all }
    private var effectiveExpiryFilter: ExpiryFilter { tracksInventory ? expiryFilter : .all }

    /// Without stock tracking nothing is "owned" in any visible way, so the whole
    /// library is listed and the stored choice is kept for when tracking returns.
    private var effectiveLibraryScope: LibraryScope { tracksInventory ? libraryScope : .all }

    /// What puts a row in My Ingredients: the user made it, bought it (a used-up
    /// purchase still counts), changed its chemistry, or starred it.
    func isOwned(_ ingredient: Ingredient, stock: StockLevels) -> Bool {
        !ingredient.isLibraryInstalled ||
            stock.hasPurchases(ingredient) ||
            ingredient.hasCustomChemistry ||
            ingredient.isFavorite
    }

    private func isInScope(_ ingredient: Ingredient, stock: StockLevels) -> Bool {
        effectiveLibraryScope == .all || isOwned(ingredient, stock: stock)
    }

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
        libraryScope = .owned
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
    /// than from `category.ingredients`, so the chips keep matching the list:
    /// library rows held back by the scope give their category no chip.
    func visibleCategories(
        _ categories: [IngredientCategory],
        in ingredients: [Ingredient],
        stock: StockLevels
    ) -> [IngredientCategory] {
        // Hidden rows are discounted here rather than at the call site, which passes
        // the unfiltered inventory: a category holding nothing but hidden rows would
        // otherwise keep a chip that leads only to "No Results".
        let inUse = Set(
            ingredients
                .filter { !$0.isHidden && isInScope($0, stock: stock) }
                .compactMap { $0.category?.persistentModelID }
        )
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

    func filtered(_ ingredients: [Ingredient], stock: StockLevels) -> [Ingredient] {
        ingredients.filter {
            !$0.isHidden && isInScope($0, stock: stock) && matchesFilters($0, stock: stock) && matchesCategory($0)
        }
    }

    /// Everything the Inventory screen draws from `ingredients`, in one pass.
    /// The list refreshes on every save to the store, and an iCloud import saves
    /// many times a second (SW-219), so the list, the chip counts and the count
    /// line must not each walk the whole inventory.
    ///
    /// - `displayed`: the filtered list, favourites first.
    /// - `categoryCounts`: how many ingredients each category chip would show
    ///   if tapped, that is the list as filtered by everything except the
    ///   category selection, so a chip's number doesn't change as the chips are
    ///   toggled. `all` is the "All" chip's total.
    /// - `summary`: the figures under the screen title, over every listed
    ///   (non-hidden, in-scope) ingredient regardless of the filters.
    /// - `libraryMatches`: while searching on My Ingredients, the library rows
    ///   outside the scope that match, so a search still reaches the whole library.
    ///
    /// Rows outside the library scope are left out of `displayed`, the counts and
    /// the summary.
    ///
    /// The summary's low and out figures only count ingredients with purchases
    /// (and only while stock is tracked), matching the stamps on the rows, so the
    /// library's never-bought ingredients don't read as out. The Out of Stock
    /// filter (`totalRemaining == 0`) does include them, so its result can be
    /// longer than the header's "out" figure.
    ///
    /// Stock comes from `stock`, built from one fetch of every purchase, rather
    /// than from each ingredient's `purchases`: after an import the purchases are
    /// faults, and walking them per ingredient fired one SQL fetch each.
    func content(for ingredients: [Ingredient], stock: StockLevels) -> IngredientListContent {
        var displayed: [Ingredient] = []
        var all = 0
        var byCategory: [PersistentIdentifier: Int] = [:]
        var total = 0
        var low = 0
        var out = 0
        var owned = 0
        var libraryMatches: [Ingredient] = []
        let offersLibraryMatches = !searchText.isEmpty && effectiveLibraryScope == .owned

        for ingredient in ingredients where !ingredient.isHidden {
            let owns = isOwned(ingredient, stock: stock)
            if owns { owned += 1 }

            guard effectiveLibraryScope == .all || owns else {
                if offersLibraryMatches, matchesFilters(ingredient, stock: stock), matchesCategory(ingredient) {
                    libraryMatches.append(ingredient)
                }
                continue
            }

            total += 1
            if tracksInventory, stock.hasPurchases(ingredient) {
                if stock.totalRemaining(ingredient) <= 0 {
                    out += 1
                } else if stock.isLowStock(ingredient) {
                    low += 1
                }
            }

            guard matchesFilters(ingredient, stock: stock) else { continue }
            all += 1
            if let id = ingredient.category?.persistentModelID {
                byCategory[id, default: 0] += 1
            }
            if matchesCategory(ingredient) {
                displayed.append(ingredient)
            }
        }

        return IngredientListContent(
            displayed: displayed.favoritesFirst,
            categoryCounts: (all, byCategory),
            summary: InventoryCountSummary(total: total, low: low, out: out),
            libraryMatches: libraryMatches,
            ownedCount: owned
        )
    }

    private func matchesCategory(_ ingredient: Ingredient) -> Bool {
        selectedCategories.isEmpty ||
            (ingredient.category.map { selectedCategories.contains($0.persistentModelID) } ?? false)
    }

    /// Every filter except the category selection, for a row that isn't hidden.
    private func matchesFilters(_ ingredient: Ingredient, stock: StockLevels) -> Bool {
        let matchesSearch = searchText.isEmpty ||
            ingredient.name.localizedCaseInsensitiveContains(searchText)

        let matchesStock: Bool
        switch effectiveStockStatus {
        case .all:        matchesStock = true
        case .inStock:    matchesStock = stock.totalRemaining(ingredient) > 0 && !stock.isLowStock(ingredient)
        case .lowStock:   matchesStock = stock.isLowStock(ingredient) && stock.totalRemaining(ingredient) > 0
        case .outOfStock: matchesStock = stock.totalRemaining(ingredient) == 0
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

        return matchesSearch && matchesStock && matchesUnit && matchesExpiry
    }
}
