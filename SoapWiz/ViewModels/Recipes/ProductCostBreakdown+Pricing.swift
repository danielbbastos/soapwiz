import Foundation

extension ProductCostBreakdown {
    /// Ingredients used whose stock has no price, so `total` understates the
    /// cost. Counted once each: one ingredient can fill rows in several groups,
    /// such as shea butter used as an oil and again as an additive.
    var unpricedIngredientCount: Int {
        let unpriced = (oils + additives + fragrances + lye).filter { $0.ingredientAmount > 0 && $0.cost <= 0 }
        return Set(unpriced.map { ObjectIdentifier($0.ingredient) }).count
    }
}
