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

    /// How many purchases show before the user taps "Show more". The rest stay a
    /// tap away so the detail page leads with the ingredient's own facts rather
    /// than a long acquisition log.
    static let purchasePreviewCount = 2

    /// Whether there are more purchases than the preview shows — i.e. whether the
    /// "Show more" affordance is needed at all.
    var hasMorePurchases: Bool {
        sortedPurchases.count > Self.purchasePreviewCount
    }

    /// The most-recent purchases, capped to the preview count until the user asks
    /// for all of them. A prefix of `sortedPurchases`, so a delete offset still
    /// lands on the same row.
    func displayedPurchases(showingAll: Bool) -> [IngredientPurchase] {
        showingAll ? sortedPurchases : Array(sortedPurchases.prefix(Self.purchasePreviewCount))
    }

    var usageEntries: [UsageEntry] {
        UsageHistory.entries(for: ingredient)
    }

    var totalRemaining: Double { ingredient.totalRemaining }

    /// Whether to show the chemistry block at all. Mirrors the form's gate
    /// (`IngredientFormViewModel.showsSapValue`): only oils carry a SAP value and
    /// a fatty-acid composition, so only oils get the panel.
    var showsChemistry: Bool {
        ingredient.category?.showsSapValue ?? false
    }

    /// True only when a real profile is on file. A nil or all-zero profile is
    /// "not specified" rather than a genuine all-zero oil, so the acid tables and
    /// the qualities chart are replaced by a note instead of a page of `0.00 %`.
    var hasFattyAcidProfile: Bool {
        guard let profile = ingredient.fattyAcidProfile else { return false }
        return !profile.isEmpty
    }

    /// The ingredient's own chemistry expressed as a one-oil blend, so the detail
    /// page reuses `RecipeStats` and the recipe stats views verbatim — the
    /// weighted sum of a single profile is that profile, and the SAP/iodine/INS
    /// fall out with it. `nil` for anything that isn't an oil.
    var chemistryStats: RecipeStats? {
        guard showsChemistry else { return nil }
        return RecipeStats(oilDrafts: [OilIngredientDraft(ingredient: ingredient, amount: 1)])
    }

    func delete(at offsets: IndexSet, context: ModelContext) {
        let purchases = sortedPurchases
        for index in offsets {
            context.delete(purchases[index])
        }
    }
}
