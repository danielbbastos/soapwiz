import SwiftData

/// What a new product row starts as: a size and the count it makes, which is
/// `nil` when no estimate can be made.
struct NewProductRowStart {
    let size: Double
    let unitSymbol: String
    let count: Int?
}

/// One of the recipe's sizes, offered as what the batch will make.
struct BatchProductSuggestion: Identifiable, Hashable {
    let id: PersistentIdentifier
    let size: Double
    let unitSymbol: String

    var label: String {
        BatchProduct.label(size: size, unitSymbol: unitSymbol)
    }

    /// The recipe's sizes that could be made as products, in the one order
    /// every screen lists them: smallest mass first, parts of a batch last.
    /// Whole batch and a single part are the batch itself, not a product.
    static func suggestions(from products: [RecipeProduct]) -> [BatchProductSuggestion] {
        products
            .filter(\.isSeparateFromBatch)
            .map { BatchProductSuggestion(id: $0.persistentModelID, size: $0.size, unitSymbol: $0.unitSymbol) }
            .sorted { lhs, rhs in
                let left = (ProductUnit(rawValue: lhs.unitSymbol)?.gramsPerUnit).map { $0 * lhs.size }
                let right = (ProductUnit(rawValue: rhs.unitSymbol)?.gramsPerUnit).map { $0 * rhs.size }
                switch (left, right) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.size < rhs.size
                }
            }
    }

    /// What a new product row starts as: the first of `suggestions`, or 100 g
    /// when the recipe has none, with the count that size makes.
    static func newRowStart(
        from suggestions: [BatchProductSuggestion],
        oneBatchWeight: Double,
        weightUnit: String,
        batchCount: Int
    ) -> NewProductRowStart {
        let size = suggestions.first?.size ?? 100
        let unitSymbol = suggestions.first?.unitSymbol ?? ProductUnit.grams.rawValue
        let count = BatchProduct.estimatedCount(
            size: size,
            unitSymbol: unitSymbol,
            oneBatchWeight: oneBatchWeight,
            weightUnit: weightUnit,
            batchCount: batchCount
        )
        return NewProductRowStart(size: size, unitSymbol: unitSymbol, count: count)
    }
}
