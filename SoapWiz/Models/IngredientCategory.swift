import Foundation
import SwiftData

@Model
final class IngredientCategory {
    enum Name {
        static let oils = "Oils"
        static let waxes = "Waxes"
        static let fats = "Fats"
        static let fragrances = "Fragrances"
        static let additives = "Additives"
        static let lyes = "Lyes"
        static let others = "Others"
    }

    var name: String

    @Relationship(deleteRule: .nullify, inverse: \Ingredient.category)
    var ingredients: [Ingredient] = []

    /// The recipe section this category's ingredients can be picked for, or
    /// `nil` when they aren't recipe line items (lye is configured separately
    /// in the recipe's lye settings, never as an additive).
    var ingredientRole: RecipeIngredientRole? {
        switch name {
        case Name.oils, Name.waxes, Name.fats: return .oil
        case Name.fragrances: return .fragrance
        case Name.lyes: return nil
        default: return .additive
        }
    }

    var showsSapValue: Bool { ingredientRole == .oil }

    init(name: String) {
        self.name = name
    }
}
