import SwiftData

@Model
final class RecipeProduct {
    var recipe: Recipe?
    var size: Double
    var unitSymbol: String

    init(size: Double, unitSymbol: String) {
        self.size = size
        self.unitSymbol = unitSymbol
    }
}
