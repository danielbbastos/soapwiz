import Foundation
import OSLog
import SwiftData

/// A lookup entity that CloudKit can duplicate: two devices offline both create
/// "Oils", they sync, and now there are two rows for one logical category.
@MainActor
protocol MergeableLookup: PersistentModel {
    /// The synced identity the merge tie-breaks on.
    var uuid: UUID { get }
    var name: String { get }

    /// Moves everything pointing at `loser` onto `winner` and folds across any
    /// scalar fields the winner is missing.
    ///
    /// Must be a pure function of the two rows. It runs independently on every
    /// device, and they only agree if none of them consults anything that can
    /// differ mid-import.
    static func adopt(_ loser: Self, into winner: Self)
}

/// Collapses the duplicate rows CloudKit cannot prevent.
///
/// CloudKit does not support unique constraints, so nothing stops two offline
/// devices creating the same category, provider, storage location, or settings
/// record. This merges each set of duplicates down to one.
///
/// The whole design rests on every device reaching the *same* answer without
/// coordinating. If one device kept row A and another kept row B, both deletions
/// would sync and both rows would be lost — worse than the duplication. So the
/// winner is the lowest `uuid`, which is synced data and therefore identical
/// everywhere, and the merge never consults relationship counts or anything else
/// that can still be arriving. Given that, running concurrently on many devices
/// converges by construction: same winner, same repointing, same deletions.
///
/// This mirrors Apple's `CoreDataCloudKitShare` sample, which likewise gives each
/// entity a `uuid` and keeps the lowest.
@MainActor
enum DuplicateMerger {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "merge")

    /// Runs the merge and swallows a failure, having logged it. A failed merge
    /// leaves duplicates in place, which is survivable — the next trigger tries
    /// again. Losing the launch to it would not be.
    static func mergeAllLoggingFailure(in context: ModelContext) {
        do {
            try mergeAll(in: context)
        } catch {
            log.error("Duplicate merge failed: \(error, privacy: .public)")
        }
    }

    /// Collapses every duplicate in the store. Safe to call repeatedly — a second
    /// pass finds only groups of one and saves nothing.
    static func mergeAll(in context: ModelContext) throws {
        var losers: [any PersistentModel] = []
        losers += try collapse(IngredientCategory.self, in: context)
        losers += try collapse(Provider.self, in: context)
        losers += try collapse(StorageLocation.self, in: context)
        losers += try collapse(RecipeCollection.self, in: context)
        losers += try collapseSettings(in: context)

        guard !losers.isEmpty else { return }

        // Two phases. If a loser's deletion reaches another device before the
        // repointing does, that device applies `.nullify` and an ingredient loses
        // its category for good — a later pass will not adopt an orphan back. Saving
        // the repoints first pushes them to CloudKit ahead of the tombstones.
        try context.save()

        for loser in losers {
            context.delete(loser)
        }
        try context.save()

        log.notice("Merged \(losers.count, privacy: .public) duplicate record(s).")
    }

    /// Groups by normalised name, keeps the lowest `uuid` of each group, and hands
    /// everything else to `adopt`. Returns the losers, still undeleted.
    private static func collapse<T: MergeableLookup>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> [T] {
        let all = try context.fetch(FetchDescriptor<T>())
        var losers: [T] = []

        for group in Dictionary(grouping: all, by: { $0.name.lookupKey }).values where group.count > 1 {
            let ordered = group.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
            guard let winner = ordered.first else { continue }
            for loser in ordered.dropFirst() {
                T.adopt(loser, into: winner)
                losers.append(loser)
            }
        }
        return losers
    }

    /// `AppSettings` is a singleton rather than a keyed lookup, and its fields
    /// merge rather than being discarded with the losing row.
    private static func collapseSettings(in context: ModelContext) throws -> [AppSettings] {
        let all = try context.fetch(FetchDescriptor<AppSettings>())
        guard all.count > 1 else { return [] }

        let ordered = all.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        guard let winner = ordered.first else { return [] }

        for loser in ordered.dropFirst() {
            // Each device creates its own settings row on first launch, so the
            // winning row is often the untouched one. Taking the first non-default
            // value keeps the setting the user actually chose.
            if winner.pvpFactor == AppSettings.defaultPVPFactor {
                winner.pvpFactor = loser.pvpFactor
            }
            // An opt-in flag joins monotonically: if reminders were switched on
            // anywhere, they stay on.
            winner.expiryNotificationsEnabled = winner.expiryNotificationsEnabled || loser.expiryNotificationsEnabled
        }
        return Array(ordered.dropFirst())
    }
}

extension IngredientCategory: MergeableLookup {
    static func adopt(_ loser: IngredientCategory, into winner: IngredientCategory) {
        let ingredients = loser.ingredients
        for ingredient in ingredients {
            ingredient.category = winner
        }
    }
}

extension Provider: MergeableLookup {
    static func adopt(_ loser: Provider, into winner: Provider) {
        let purchases = loser.purchases
        for purchase in purchases {
            purchase.provider = winner
        }
        if winner.website.isEmpty { winner.website = loser.website }
        if winner.notes.isEmpty { winner.notes = loser.notes }
    }
}

extension RecipeCollection: MergeableLookup {
    /// Membership is many-to-many, so the two rows can already share a recipe —
    /// the union is taken rather than appending blindly, which would file the
    /// same recipe under the winner twice.
    static func adopt(_ loser: RecipeCollection, into winner: RecipeCollection) {
        let recipes = loser.recipes
        for recipe in recipes where !recipe.collections.contains(where: { $0 === winner }) {
            recipe.collections.append(winner)
        }
        if winner.colorName.isEmpty { winner.colorName = loser.colorName }
    }
}

extension StorageLocation: MergeableLookup {
    static func adopt(_ loser: StorageLocation, into winner: StorageLocation) {
        let purchases = loser.purchases
        for purchase in purchases {
            purchase.storageLocation = winner
        }
        if winner.locationDescription.isEmpty {
            winner.locationDescription = loser.locationDescription
        }
    }
}
