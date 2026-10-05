import Foundation
import SwiftData

@MainActor
@Observable
final class CategoryFormViewModel {
    var name: String = ""

    let category: IngredientCategory?
    private let initialName: String

    init(category: IngredientCategory? = nil) {
        self.category = category
        initialName = category?.name ?? ""
        name = initialName
    }

    var isEditing: Bool { category != nil }
    /// Whether anything was typed, which stops a swipe from closing the sheet.
    var isDirty: Bool { name != initialName }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among categories: [IngredientCategory]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return categories.contains { $0.name.lookupKey == trimmedName.lookupKey && $0 != category }
    }

    func isValid(among categories: [IngredientCategory]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: categories)
    }

    @discardableResult
    func save(context: ModelContext) -> IngredientCategory {
        if let category {
            if category.isRenamable {
                category.name = trimmedName
            }
            return category
        }
        let newCategory = IngredientCategory(name: trimmedName)
        context.insert(newCategory)
        return newCategory
    }
}
