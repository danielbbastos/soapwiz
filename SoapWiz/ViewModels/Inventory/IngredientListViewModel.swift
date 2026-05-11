import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IngredientListViewModel {
    var showingAddIngredient: Bool = false
    var editMode: EditMode = .inactive
    var selection: Set<PersistentIdentifier> = []

    func delete(at offsets: IndexSet, in ingredients: [Ingredient], context: ModelContext) {
        for index in offsets {
            context.delete(ingredients[index])
        }
    }

    func deleteSelected(in ingredients: [Ingredient], context: ModelContext) {
        for id in selection {
            if let match = ingredients.first(where: { $0.persistentModelID == id }) {
                context.delete(match)
            }
        }
        selection.removeAll()
        editMode = .inactive
    }
}
