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
    var showingFilters: Bool = false
    var pendingIngredient: Ingredient?
    var editMode: EditMode = .inactive
    var selection: Set<PersistentIdentifier> = []
    var confirmingDelete: [Ingredient] = []

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

    func delete(_ ingredient: Ingredient, context: ModelContext) {
        if ingredient.purchases.isEmpty {
            context.delete(ingredient)
        } else {
            confirmingDelete = [ingredient]
        }
    }

    func deleteSelected(in ingredients: [Ingredient], context: ModelContext) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        if targets.contains(where: { !$0.purchases.isEmpty }) {
            confirmingDelete = targets
        } else {
            targets.forEach { context.delete($0) }
            selection.removeAll()
            editMode = .inactive
        }
    }

    func confirmDelete(context: ModelContext) {
        confirmingDelete.forEach { context.delete($0) }
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
