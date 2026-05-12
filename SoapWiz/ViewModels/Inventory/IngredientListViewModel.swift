import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IngredientListViewModel {
    var showingAddIngredient: Bool = false
    var pendingIngredient: Ingredient?
    var editMode: EditMode = .inactive
    var selection: Set<PersistentIdentifier> = []
    var confirmingDelete: [Ingredient] = []
    var showLowStockOnly: Bool = false

    func delete(_ ingredient: Ingredient, context: ModelContext) {
        if ingredient.batches.isEmpty {
            context.delete(ingredient)
        } else {
            confirmingDelete = [ingredient]
        }
    }

    func deleteSelected(in ingredients: [Ingredient], context: ModelContext) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        if targets.contains(where: { !$0.batches.isEmpty }) {
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
