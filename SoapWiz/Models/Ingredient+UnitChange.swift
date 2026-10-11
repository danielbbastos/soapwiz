import Foundation

extension Ingredient {
    /// Switches the ingredient's unit, converting stock to match when the two
    /// units measure the same kind of thing (ml ↔ L, g ↔ kg), so 20,500 ml becomes
    /// 20.5 L rather than 20,500 L. Each purchase's `quantity` and `remainingAmount`
    /// are converted; `totalPrice` is left alone, which makes `pricePerUnit` follow
    /// the new unit on its own.
    ///
    /// A change across kinds (g ↔ ml, or to or from a count) can't be converted
    /// without a density, so only the unit changes and the numbers stay as they
    /// were.
    ///
    /// The low-stock threshold is not touched here: the edit form shows it as text
    /// and converts that text as the unit is picked, so the user sees the new
    /// number before saving.
    ///
    /// Batch line items carry their own unit and are deliberately left alone.
    func changeUnit(to newUnit: String) {
        guard newUnit != unit else { return }
        let oldUnit = unit
        for purchase in purchases {
            if let quantity = IngredientUnitConverter.convertSameKind(purchase.quantity, from: oldUnit, to: newUnit),
               let remaining = IngredientUnitConverter.convertSameKind(purchase.remainingAmount, from: oldUnit, to: newUnit) {
                purchase.quantity = quantity
                purchase.remainingAmount = remaining
            }
        }
        unit = newUnit
    }
}
