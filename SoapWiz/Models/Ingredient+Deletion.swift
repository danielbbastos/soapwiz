import SwiftData

extension Ingredient {
    /// Deletes the ingredient together with its purchases and recipe rows — what
    /// a `.cascade` rule used to do, now done only when the user asks for it.
    /// Batch line items and shopping list lines are left alone: history outlives
    /// the ingredient, and a list line survives as a plain name.
    func deleteWithOwnedRows(in context: ModelContext) {
        purchases.forEach { context.delete($0) }
        recipeIngredients.forEach { context.delete($0) }
        context.delete(self)
    }
}
