import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var selectedUnit: QuantityUnit?
    var selectedCategory: IngredientCategory?
    var lowStockThreshold: String = ""

    let ingredient: Ingredient?

    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        if let ingredient {
            name = ingredient.name
            selectedUnit = ingredient.unit
            selectedCategory = ingredient.category
            if let threshold = ingredient.lowStockThreshold {
                lowStockThreshold = threshold.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
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
        let parsedThreshold = Double(lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        if let ingredient {
            ingredient.name = trimmedName
            ingredient.category = selectedCategory
            ingredient.unit = selectedUnit
            ingredient.lowStockThreshold = parsedThreshold
            return nil
        } else {
            let newIngredient = Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit)
            newIngredient.lowStockThreshold = parsedThreshold
            context.insert(newIngredient)
            return newIngredient
        }
    }
}
