import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientDetailViewModel {
    var showingAddBatch: Bool = false
    var showingEditIngredient: Bool = false

    let ingredient: Ingredient

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
    }

    var sortedBatches: [IngredientBatch] {
        ingredient.batches.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
    }

    var totalRemaining: Double { ingredient.totalRemaining }

    func delete(at offsets: IndexSet, context: ModelContext) {
        let batches = sortedBatches
        for index in offsets {
            context.delete(batches[index])
        }
    }
}
