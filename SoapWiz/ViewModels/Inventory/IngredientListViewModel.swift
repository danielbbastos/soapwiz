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

    /// Being used by a recipe blocks deletion outright and takes precedence over the
    /// remaining-stock confirmation: losing stock is recoverable, silently gutting a
    /// recipe's oil percentages — and with them its lye calculation — is not.
    func delete(_ ingredient: Ingredient, context: ModelContext) {
        if ingredient.isUsedInRecipes {
            deleteBlockedIngredients = [ingredient]
        } else if ingredient.purchases.isEmpty {
            context.delete(ingredient)
        } else {
            confirmingDelete = [ingredient]
        }
    }

    /// If any selected ingredient is used by a recipe, nothing is deleted — a partial
    /// delete would be harder to reason about than none at all.
    func deleteSelected(in ingredients: [Ingredient], context: ModelContext) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        let blocked = targets.filter(\.isUsedInRecipes)
        if !blocked.isEmpty {
            deleteBlockedIngredients = blocked
        } else if targets.contains(where: { !$0.purchases.isEmpty }) {
            confirmingDelete = targets
        } else {
            targets.forEach { context.delete($0) }
            selection.removeAll()
            editMode = .inactive
        }
    }

    /// Explains which recipes are in the way, so the user knows where to go next.
    var deleteBlockedMessage: String {
        guard !deleteBlockedIngredients.isEmpty else { return "" }

        if deleteBlockedIngredients.count == 1, let ingredient = deleteBlockedIngredients.first {
            let recipes = ingredient.recipesUsingThis.map(\.name).sorted()
            let recipeWord = recipes.count == 1 ? "recipe" : "recipes"
            let target = recipes.count == 1 ? "that recipe" : "those recipes"
            return "\"\(ingredient.name)\" is used in \(recipes.count) \(recipeWord): "
                + "\(recipes.formatted()). Remove it from \(target) first."
        }

        let names = deleteBlockedIngredients.map(\.name).sorted()
        return "\(names.formatted()) are used in recipes. Remove them from those recipes first."
    }

    func confirmDelete(context: ModelContext) {
        confirmingDelete.forEach { context.delete($0) }
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
