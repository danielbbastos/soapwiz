import Foundation
import SwiftData

@Model
final class IngredientCategory {
    var name: String

    @Relationship(deleteRule: .nullify, inverse: \Ingredient.category)
    var ingredients: [Ingredient] = []

    init(name: String) {
        self.name = name
    }
}
