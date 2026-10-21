import Foundation

/// What one inventory row shows of an ingredient's purchases, as a value.
///
/// A row that read `ingredient.purchases` itself was never redrawn when a
/// purchase was deleted or arrived from CloudKit: neither goes through the
/// ingredient's property setters, so nothing is observed to change. Handed to
/// the row as an input instead, a change in stock is a change in the row's
/// inputs, and SwiftUI redraws it exactly then (SW-317).
struct IngredientStock: Equatable {
    let remaining: Double
    let hasPurchases: Bool
    /// Every purchase's expiry date, oldest first. Sorted so that the same
    /// purchases compare equal whatever order the fetch returned them in.
    let expiries: [Date]

    static let none = IngredientStock(remaining: 0, hasPurchases: false, expiries: [])
}
