import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientDetailViewModel {
    var showingAddPurchase: Bool = false
    var showingEditIngredient: Bool = false

    let ingredient: Ingredient

    init(ingredient: Ingredient, showingAddPurchase: Bool = false) {
        self.ingredient = ingredient
        self.showingAddPurchase = showingAddPurchase
    }

    var sortedPurchases: [IngredientPurchase] {
        ingredient.purchases.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
    }

    var totalRemaining: Double { ingredient.totalRemaining }

    func delete(at offsets: IndexSet, context: ModelContext) {
        let purchases = sortedPurchases
        for index in offsets {
            context.delete(purchases[index])
        }
    }
}
