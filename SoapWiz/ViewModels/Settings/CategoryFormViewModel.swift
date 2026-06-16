import Foundation
import SwiftData

@MainActor
@Observable
final class CategoryFormViewModel {
    var name: String = ""

    let category: IngredientCategory?

    init(category: IngredientCategory? = nil) {
        self.category = category
        if let category {
            name = category.name
        }
    }

    var isEditing: Bool { category != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among categories: [IngredientCategory]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return categories.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != category }
    }

    func isValid(among categories: [IngredientCategory]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: categories)
    }

    @discardableResult
    func save(context: ModelContext) -> IngredientCategory {
        if let category {
            category.name = trimmedName
            return category
        }
        let newCategory = IngredientCategory(name: trimmedName)
        context.insert(newCategory)
        return newCategory
    }
}
