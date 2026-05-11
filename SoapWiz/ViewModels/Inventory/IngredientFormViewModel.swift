import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var selectedUnit: QuantityUnit?
    var selectedCategory: IngredientCategory?

    let ingredient: Ingredient?

    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        if let ingredient {
            name = ingredient.name
            selectedUnit = ingredient.unit
            selectedCategory = ingredient.category
        }
    }

    var isEditing: Bool { ingredient != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var isValid: Bool { !trimmedName.isEmpty && selectedUnit != nil }

    func save(context: ModelContext) {
        if let ingredient {
            ingredient.name = trimmedName
            ingredient.category = selectedCategory
            ingredient.unit = selectedUnit
        } else {
            context.insert(Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit))
        }
    }
}
