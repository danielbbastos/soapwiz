import SwiftData

extension Ingredient {
    /// Deletes the ingredient together with its purchases and recipe rows — what
    /// a `.cascade` rule used to do, now done only when the user asks for it.
    /// Batch line items are left alone: history outlives the ingredient.
    func deleteWithOwnedRows(in context: ModelContext) {
        purchases.forEach { context.delete($0) }
        recipeIngredients.forEach { context.delete($0) }
        context.delete(self)
    }
}
