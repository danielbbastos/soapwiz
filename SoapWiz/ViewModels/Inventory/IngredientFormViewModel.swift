import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var unit: String = ""
    var selectedCategory: IngredientCategory?

    let ingredient: Ingredient?

    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        if let ingredient {
            name = ingredient.name
            unit = ingredient.unit
            selectedCategory = ingredient.category
        }
    }

    var isEditing: Bool { ingredient != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedUnit: String { unit.trimmingCharacters(in: .whitespaces) }

    var isValid: Bool { !trimmedName.isEmpty && !trimmedUnit.isEmpty }

    func save(context: ModelContext) {
        if let ingredient {
            ingredient.name = trimmedName
            ingredient.category = selectedCategory
            ingredient.unit = trimmedUnit
        } else {
            context.insert(Ingredient(name: trimmedName, category: selectedCategory, unit: trimmedUnit))
        }
    }
}
