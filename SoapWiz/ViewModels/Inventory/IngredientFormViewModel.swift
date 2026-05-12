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

    var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        return selectedUnit != nil || (isEditing && ingredient?.unit == nil)
    }

    @discardableResult
    func save(context: ModelContext) -> Ingredient? {
        if let ingredient {
            ingredient.name = trimmedName
            ingredient.category = selectedCategory
            ingredient.unit = selectedUnit
            return nil
        } else {
            let newIngredient = Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit)
            context.insert(newIngredient)
            return newIngredient
        }
    }
}
