import Foundation
import SwiftData

@Model
final class QuantityUnit {
    var name: String
    var symbol: String

    @Relationship(deleteRule: .nullify, inverse: \Ingredient.unit)
    var ingredients: [Ingredient] = []

    init(name: String, symbol: String) {
        self.name = name
        self.symbol = symbol
    }
}
