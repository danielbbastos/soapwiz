import Foundation
import OSLog
import SwiftData

/// Gives every ingredient its own `uuid` after the migration that added the field.
///
/// Same cause as `RecipeIdentityBackfill`: a defaulted attribute is one value
/// recorded in the model, so every ingredient that existed before the field came
/// out of the migration sharing one identity. The merge that collapses duplicate
/// library ingredients picks its survivor by `uuid`, and a tie gives it nothing
/// to pick on.
///
/// Only rows that *collide* are re-minted, so an inventory created after the
/// field existed is never touched, and a second pass writes nothing.
@MainActor
enum IngredientIdentityBackfill {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "backfill")

    /// Runs the pass and swallows a failure, having logged it. Shared identities
    /// only matter once duplicates need merging, which is survivable; losing the
    /// launch to it would not be.
    static func repairSharedIdentitiesLoggingFailure(in context: ModelContext) {
        do {
            try repairSharedIdentities(in: context)
        } catch {
            log.error("Ingredient identity backfill failed: \(error, privacy: .public)")
        }
    }

    /// Re-mints every ingredient in a group that shares a uuid, and returns how
    /// many were changed.
    @discardableResult
    static func repairSharedIdentities(in context: ModelContext) throws -> Int {
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        var repaired = 0

        for group in Dictionary(grouping: ingredients, by: \.uuid).values where group.count > 1 {
            for ingredient in group {
                ingredient.uuid = UUID()
                repaired += 1
            }
        }

        guard repaired > 0 else { return 0 }
        try context.save()
        log.notice("Re-minted \(repaired, privacy: .public) shared ingredient identity/identities.")
        return repaired
    }
}
