import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientDetailViewModel {
    var showingAddPurchase: Bool = false
    var showingEditIngredient: Bool = false

    /// Swapped onto the surviving row when the duplicate merge deletes the one
    /// this screen was opened with. Every field the screen draws is read off it,
    /// so a detached reference here empties the whole page — no purchases, no
    /// stock, no usage — rather than just one section.
    private(set) var ingredient: Ingredient

    /// The merge key, read while the row is certainly still in the store.
    /// Reading a stored attribute off a detached model is not safe, so it cannot
    /// be recovered later. See `LiveIngredient`.
    private let ingredientSlug: String

    init(ingredient: Ingredient, showingAddPurchase: Bool = false) {
        self.ingredient = ingredient
        self.ingredientSlug = ingredient.librarySlug
        self.showingAddPurchase = showingAddPurchase
    }

    /// Follows the merge onto the row that survived it.
    ///
    /// A no-op while the captured row is still in the store, which is every case
    /// but the first sync on a device that joined an existing account. When
    /// nothing resolves the captured row is kept: it was deleted outright rather
    /// than merged, and there is no survivor to show instead.
    ///
    /// Assigning is what redraws the screen — `ingredient` is observed, and the
    /// row replacing it is an object the view has never read.
    func resolve(in context: ModelContext) {
        guard let live = LiveIngredient.resolve(ingredient, slug: ingredientSlug, in: context),
              live !== ingredient else { return }
        ingredient = live
    }

    var sortedPurchases: [IngredientPurchase] {
        ingredient.purchases.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
    }

    var usageEntries: [UsageEntry] {
        UsageHistory.entries(for: ingredient)
    }

    var totalRemaining: Double { ingredient.totalRemaining }

    func delete(at offsets: IndexSet, context: ModelContext) {
        let purchases = sortedPurchases
        for index in offsets {
            context.delete(purchases[index])
        }
    }
}
