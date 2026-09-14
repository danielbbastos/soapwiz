import Foundation
import OSLog
import SwiftData

/// Gives every recipe its own `uuid` after the migration that added the field.
///
/// `Recipe.uuid` is defaulted rather than optional, which is what makes it
/// CloudKit-safe — but a defaulted attribute is one value recorded in the model,
/// not an expression re-evaluated per row. Core Data backfills the new column
/// with that single value, so a library that already held recipes when this
/// shipped comes out of the migration with all of them sharing one identity.
/// Exporting two would claim they were the same recipe.
///
/// Only rows that *collide* are re-minted, so a library created after the field
/// existed is never touched. Idempotent by construction: once every uuid is
/// distinct there are no groups left to find and the pass writes nothing.
///
/// Two devices that migrate offline mint different values for the same recipe,
/// and CloudKit settles it per record the way it settles any other field. There
/// is no prior agreement to preserve — the uuid did not exist before — so
/// converging on either device's value is correct.
@MainActor
enum RecipeIdentityBackfill {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "backfill")

    /// Runs the pass and swallows a failure, having logged it. A library left
    /// with shared identities still works everywhere except sharing, which is
    /// survivable; losing the launch to it would not be.
    static func repairSharedIdentitiesLoggingFailure(in context: ModelContext) {
        do {
            try repairSharedIdentities(in: context)
        } catch {
            log.error("Recipe identity backfill failed: \(error, privacy: .public)")
        }
    }

    /// Re-mints every recipe in a group that shares a uuid, and returns how many
    /// were changed.
    ///
    /// The whole group is re-minted rather than all-but-one. Keeping a survivor
    /// would save one write and cost a rule about which row deserves to keep a
    /// value that no device agrees on anyway.
    @discardableResult
    static func repairSharedIdentities(in context: ModelContext) throws -> Int {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        var repaired = 0

        for group in Dictionary(grouping: recipes, by: \.uuid).values where group.count > 1 {
            for recipe in group {
                recipe.uuid = UUID()
                repaired += 1
            }
        }

        guard repaired > 0 else { return 0 }
        try context.save()
        log.notice("Re-minted \(repaired, privacy: .public) shared recipe identity/identities.")
        return repaired
    }
}
