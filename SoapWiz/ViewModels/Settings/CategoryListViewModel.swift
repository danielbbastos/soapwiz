import Foundation
import SwiftData

@MainActor
@Observable
final class CategoryListViewModel {
    var showingAddCategory: Bool = false
    var categoryToEdit: IngredientCategory?
    var deleteBlockedCategory: IngredientCategory?

    func delete(at offsets: IndexSet, in categories: [IngredientCategory], context: ModelContext) {
        for index in offsets {
            let category = categories[index]
            if category.ingredients.isEmpty {
                context.delete(category)
            } else {
                deleteBlockedCategory = category
            }
        }
    }
}
