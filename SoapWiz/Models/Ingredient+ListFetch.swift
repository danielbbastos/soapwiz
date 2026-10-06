import Foundation
import SwiftData

extension Ingredient {
    /// The fetch behind every screen that lists all ingredients.
    ///
    /// SwiftData reads each fetched ingredient's to-many relationships while it
    /// builds the results, and on its own it does that one SQL query per
    /// ingredient per relationship. Prefetching turns that into one query per
    /// relationship. It matters because the list refetches on every save, and
    /// an iCloud import saves many times a second (SW-219).
    static var listDescriptor: FetchDescriptor<Ingredient> {
        var descriptor = FetchDescriptor<Ingredient>(sortBy: [SortDescriptor(\.name)])
        descriptor.relationshipKeyPathsForPrefetching = [
            \.purchasesStorage,
            \.recipeIngredientsStorage,
            \.batchLineItemsStorage,
            \.recipesUsingAsLyeStorage,
            \.recipesUsingAsKOHLyeStorage,
            \.recipesUsingAsNeutralizerStorage
        ]
        return descriptor
    }
}
