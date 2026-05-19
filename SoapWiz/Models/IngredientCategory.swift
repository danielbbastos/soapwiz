import Foundation
import SwiftData

@Model
final class IngredientCategory {
    var name: String

    @Relationship(deleteRule: .nullify, inverse: \Ingredient.category)
    var ingredients: [Ingredient] = []

    var showsSapValue: Bool {
        ["Oils", "Waxes", "Fats"].contains(name)
    }

    init(name: String) {
        self.name = name
    }
}
