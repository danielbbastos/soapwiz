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

    /// Stable identity across devices, so a name collision arriving from CloudKit
    /// can be collapsed the same way everywhere. See `DuplicateMerger`.
    var uuid: UUID = UUID()
    var name: String = ""

    /// Optional for CloudKit; read and write through `ingredients`. Neither name
    /// is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "ingredients", inverse: \Ingredient.category)
    var ingredientsStorage: [Ingredient]? = []

    var ingredients: [Ingredient] {
        get { ingredientsStorage ?? [] }
        set { ingredientsStorage = newValue }
    }

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
