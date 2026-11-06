import SwiftData

@Model
final class RecipeProduct {
    var recipe: Recipe?
    var size: Double = 0
    var unitSymbol: String = ""

    init(size: Double, unitSymbol: String) {
        self.size = size
        self.unitSymbol = unitSymbol
    }

    /// Whether this size is one the maker could make as a product of its own;
    /// see `ProductUnit.isSeparateFromBatch(size:unitSymbol:)`.
    var isSeparateFromBatch: Bool {
        ProductUnit.isSeparateFromBatch(size: size, unitSymbol: unitSymbol)
    }
}
