import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    /// Posted once a merge has committed deletions, so a screen still holding a
    /// row that was merged away can resolve itself onto the survivor.
    ///
    /// Deliberately not `.NSPersistentStoreRemoteChange`, which is what the merge
    /// is debounced *behind*: a screen resolving on that signal would usually run
    /// before the deletion had happened and find nothing to do.
    ///
    /// Nothing is posted when a pass finds no duplicates, which is the common
    /// case — only the first sync on a device that joined an existing account
    /// deletes anything.
    static let duplicatesMerged = Notification.Name("pt.daphnia.SoapWiz.duplicatesMerged")
}

/// A lookup entity that CloudKit can duplicate: two devices offline both create
/// "Oils", they sync, and now there are two rows for one logical category.
@MainActor
protocol MergeableLookup: PersistentModel {
    /// The synced identity the merge tie-breaks on.
    var uuid: UUID { get }
    var name: String { get }

    /// What makes two rows the same row. Rows sharing a key collapse; `nil`
    /// opts a row out of merging entirely.
    ///
    /// Must be derived from synced data alone. Two devices decide independently
    /// and only agree if neither consults anything local.
    var mergeKey: String? { get }

    /// Moves everything pointing at `loser` onto `winner` and folds across any
    /// scalar fields the winner is missing.
    ///
    /// Must be a pure function of the two rows. It runs independently on every
    /// device, and they only agree if none of them consults anything that can
    /// differ mid-import.
    static func adopt(_ loser: Self, into winner: Self)
}

extension MergeableLookup {
    /// Lookup rows are the same row when they read the same to the user, so the
    /// normalised name is the key. `Ingredient` overrides this.
    var mergeKey: String? { name.lookupKey }
}

/// Collapses the duplicate rows CloudKit cannot prevent.
///
/// CloudKit does not support unique constraints, so nothing stops two offline
/// devices creating the same category, provider, storage location, or settings
/// record. This merges each set of duplicates down to one.
///
/// Ingredients duplicate for a second reason that is not a race but a
/// certainty: every device installs the bundled library before CloudKit's first
/// import can tell it the account already has one, so a device joining an
/// existing account always holds two of each. The same happens on any update
/// that adds catalog entries. Those collapse by `librarySlug`.
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
        losers += try collapse(Ingredient.self, in: context)
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

        // After the deletions are committed, never before: a screen resolving
        // itself against a store that still holds the losers would simply find
        // the row it already has.
        NotificationCenter.default.post(name: .duplicatesMerged, object: nil)
    }

    /// Groups by `mergeKey`, keeps the lowest `uuid` of each group, and hands
    /// everything else to `adopt`. Returns the losers, still undeleted.
    private static func collapse<T: MergeableLookup>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> [T] {
        var losers: [T] = []

        let all = try context.fetch(FetchDescriptor<T>())
        let keyed = all.compactMap { model in model.mergeKey.map { (key: $0, model: model) } }
        for group in Dictionary(grouping: keyed, by: \.key).values {
            let ordered = group.map(\.model).sorted { $0.uuid.uuidString < $1.uuid.uuidString }
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

extension Ingredient: MergeableLookup {
    /// Library rows pair by the slug they were installed from, never by name:
    /// the slug is the one identity the catalog guarantees is the same on every
    /// device, and it survives the user renaming the row.
    ///
    /// A user-created ingredient has no slug and opts out entirely. Matching one
    /// against the catalog by name would delete a row the user made deliberately
    /// — along with the purchases and history hanging off it — to save them a
    /// duplicate in a list, which is a destructive answer to a cosmetic problem.
    /// Linking such a row to an entry is the installer's job, and it only does
    /// so while no row carries that slug yet, so it never deletes anything.
    /// See SW-140.
    var mergeKey: String? { librarySlug.isEmpty ? nil : librarySlug }

    static func adopt(_ loser: Ingredient, into winner: Ingredient) {
        let purchases = loser.purchases
        for purchase in purchases {
            purchase.ingredient = winner
        }
        let recipeIngredients = loser.recipeIngredients
        for recipeIngredient in recipeIngredients {
            recipeIngredient.ingredient = winner
        }
        let lineItems = loser.batchLineItems
        for lineItem in lineItems {
            lineItem.ingredient = winner
        }
        let lyeRecipes = loser.recipesUsingAsLye
        for recipe in lyeRecipes {
            recipe.lyeIngredient = winner
        }
        let kohLyeRecipes = loser.recipesUsingAsKOHLye
        for recipe in kohLyeRecipes {
            recipe.kohLyeIngredient = winner
        }

        // A rename is the user's, and it must not be handed back to the catalog's
        // name just because the renamed copy happened to draw the higher `uuid`.
        // The bundled name for the slug is what tells the two apart: a row still
        // carrying it was never renamed, so it yields to one that was. Two rows
        // renamed differently leave the lowest `uuid` to decide, as everywhere
        // else, and an unknown slug changes nothing.
        //
        // This is the one place the merge reads something outside the two rows.
        // The catalog is fixed for a given build rather than arriving mid-import,
        // so devices on the same version still agree; ones on different versions
        // can disagree about a name, which last-writer-wins settles. That is a
        // cosmetic divergence, not the lost-row kind the `uuid` rule exists to
        // prevent.
        let bundledName = IngredientLibrary.bundledName(for: winner.librarySlug)
        if let bundledName, winner.name == bundledName, loser.name != bundledName {
            winner.name = loser.name
        }

        // Both flags are opt-in, so they join rather than being decided by the
        // winner: hiding or favouriting on any device holds after the merge.
        winner.isFavorite = winner.isFavorite || loser.isFavorite
        winner.isHidden = winner.isHidden || loser.isHidden

        // A customised row is the only one carrying values the user chose, so it
        // hands them over to a winner still on the bundled ones. Two customised
        // rows leave the lowest `uuid` to decide, as everywhere else.
        if loser.hasCustomChemistry, !winner.hasCustomChemistry {
            winner.sapValue = loser.sapValue
            winner.kohSapValue = loser.kohSapValue
            winner.density = loser.density
            winner.fattyAcidProfile = loser.fattyAcidProfile
            winner.hasCustomChemistry = true
        }

        // The thumbnail is derived from the photo, so the two move together or a
        // row ends up showing a thumbnail of a different bottle.
        if winner.imageData == nil {
            winner.imageData = loser.imageData
            winner.thumbnailData = loser.thumbnailData
        }
        if winner.code.isEmpty { winner.code = loser.code }
        if winner.lowStockThreshold == nil { winner.lowStockThreshold = loser.lowStockThreshold }
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
