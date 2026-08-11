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
    var deleteBlockedIngredients: [Ingredient] = []

    var searchText: String = ""
    var selectedCategories: Set<PersistentIdentifier> = []
    var stockStatus: StockStatusFilter = .all
    var selectedUnits: Set<IngredientUnit> = []
    var expiryFilter: ExpiryFilter = .all

    var hasActiveFilters: Bool { activeFilterCount > 0 }

    var activeFilterCount: Int {
        (selectedCategories.isEmpty ? 0 : 1) +
        (stockStatus == .all ? 0 : 1) +
        (selectedUnits.isEmpty ? 0 : 1) +
        (expiryFilter == .all ? 0 : 1)
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
    }

    func filtered(_ ingredients: [Ingredient]) -> [Ingredient] {
        ingredients.filter { ingredient in
            let matchesSearch = searchText.isEmpty ||
                ingredient.name.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategories.isEmpty ||
                (ingredient.category.map { selectedCategories.contains($0.persistentModelID) } ?? false)

            let matchesStock: Bool
            switch stockStatus {
            case .all:        matchesStock = true
            case .inStock:    matchesStock = ingredient.totalRemaining > 0 && !ingredient.isLowStock
            case .lowStock:   matchesStock = ingredient.isLowStock && ingredient.totalRemaining > 0
            case .outOfStock: matchesStock = ingredient.totalRemaining == 0
            }

            let matchesUnit = selectedUnits.isEmpty ||
                selectedUnits.contains(where: { $0.rawValue == ingredient.unit })

            let matchesExpiry: Bool
            switch expiryFilter {
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

    /// At most this many names are spelled out before the rest are summarised.
    /// Alert messages don't scroll, so an unbounded list stops being readable —
    /// the exact count carries the information anyway.
    private static let maxNamesListed = 3

    /// Being used by a recipe blocks deletion outright and takes precedence over the
    /// remaining-stock confirmation: losing stock is recoverable, silently gutting a
    /// recipe's oil percentages — and with them its lye calculation — is not.
    ///
    /// Everything else routes through `confirmingDelete`. An ingredient carries sap
    /// values, density and a fatty-acid profile that are tedious to re-enter, and
    /// there is no undo, so no deletion happens on a single tap.
    func delete(_ ingredient: Ingredient) {
        if ingredient.isUsedInRecipes {
            deleteBlockedIngredients = [ingredient]
        } else {
            confirmingDelete = [ingredient]
        }
    }

    /// If any selected ingredient is used by a recipe, nothing is deleted — a partial
    /// delete would be harder to reason about than none at all.
    func deleteSelected(in ingredients: [Ingredient]) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        guard !targets.isEmpty else { return }
        let blocked = targets.filter(\.isUsedInRecipes)
        if !blocked.isEmpty {
            deleteBlockedIngredients = blocked
        } else {
            confirmingDelete = targets
        }
    }

    /// Explains which recipes are in the way, so the user knows where to go next.
    var deleteBlockedMessage: String {
        guard !deleteBlockedIngredients.isEmpty else { return "" }

        if deleteBlockedIngredients.count == 1, let ingredient = deleteBlockedIngredients.first {
            let recipes = ingredient.recipesUsingThis.map(\.name).sorted()
            let target = recipes.count == 1 ? "that recipe" : "those recipes"
            return "\"\(ingredient.name)\" is used in \(Self.abbreviated(recipes)). "
                + "Remove it from \(target) first."
        }

        let names = deleteBlockedIngredients.map(\.name).sorted()
        return "\(Self.abbreviated(names)) are used in recipes. Remove them from those recipes first."
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

    /// Spells out the first few names and summarises the rest. The overflow form joins
    /// manually because `ListFormatStyle` has no notion of truncation, and appending to
    /// its output would read "A, B, and C and 22 others".
    private static func abbreviated(_ names: [String]) -> String {
        guard names.count > maxNamesListed else { return names.formatted() }
        let remaining = names.count - maxNamesListed
        let otherWord = remaining == 1 ? "other" : "others"
        return names.prefix(maxNamesListed).joined(separator: ", ") + " and \(remaining) \(otherWord)"
    }

    func confirmDelete(context: ModelContext) {
        confirmingDelete.forEach { context.delete($0) }
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
