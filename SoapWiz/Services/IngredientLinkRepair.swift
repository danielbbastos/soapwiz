import Foundation
import SwiftData

/// A row that points at an `Ingredient` and remembers that ingredient's library
/// slug, so it can find its way back if the link is cut.
@MainActor
protocol IngredientLinked: PersistentModel {
    var ingredient: Ingredient? { get set }
    var ingredientSlug: String { get set }
}

extension RecipeIngredient: IngredientLinked {}
extension IngredientPurchase: IngredientLinked {}

/// Keeps recipe rows and purchases attached to a library ingredient across the
/// duplicate merge.
///
/// The merge deletes a losing copy on one device and re-points its rows on
/// another, and CloudKit can deliver the deletion before the re-pointing. With
/// `.nullify` rules that only detaches the rows instead of deleting them (SW-165);
/// this puts them back on the surviving copy, found by the slug each row carries.
@MainActor
enum IngredientLinkRepair {
    /// Records each attached row's slug. Runs before the merge so the slug
    /// travels in the same save as any re-pointing.
    static func stampSlugs(in context: ModelContext) throws -> Bool {
        let recipeRows = try stamp(RecipeIngredient.self, in: context)
        let purchases = try stamp(IngredientPurchase.self, in: context)
        return recipeRows || purchases
    }

    /// Re-attaches detached rows to the library row carrying their slug. Runs
    /// after the merge's deletions, when at most one row per slug is left — and
    /// picks the lowest `uuid` regardless, the row the merge keeps.
    static func reattachDetachedRows(in context: ModelContext) throws -> Bool {
        let library = try context.fetch(FetchDescriptor<Ingredient>()).filter { !$0.librarySlug.isEmpty }
        let survivors = Dictionary(grouping: library, by: \.librarySlug).compactMapValues { rows in
            rows.min { $0.uuid.uuidString < $1.uuid.uuidString }
        }
        guard !survivors.isEmpty else { return false }

        let recipeRows = try reattach(RecipeIngredient.self, to: survivors, in: context)
        let purchases = try reattach(IngredientPurchase.self, to: survivors, in: context)
        return recipeRows || purchases
    }

    private static func stamp<T: IngredientLinked>(_ type: T.Type, in context: ModelContext) throws -> Bool {
        var changed = false
        for row in try context.fetch(FetchDescriptor<T>()) {
            guard let ingredient = row.ingredient, row.ingredientSlug != ingredient.librarySlug else { continue }
            row.ingredientSlug = ingredient.librarySlug
            changed = true
        }
        return changed
    }

    private static func reattach<T: IngredientLinked>(
        _ type: T.Type,
        to survivors: [String: Ingredient],
        in context: ModelContext
    ) throws -> Bool {
        var changed = false
        for row in try context.fetch(FetchDescriptor<T>()) where row.ingredient == nil {
            guard let survivor = survivors[row.ingredientSlug] else { continue }
            row.ingredient = survivor
            changed = true
        }
        return changed
    }
}
