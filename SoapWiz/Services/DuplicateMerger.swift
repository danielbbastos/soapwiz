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
    static func mergeAllLoggingFailure(
        from library: IngredientLibrary = .bundled,
        in context: ModelContext
    ) {
        do {
            try mergeAll(from: library, in: context)
        } catch {
            log.error("Duplicate merge failed: \(error, privacy: .public)")
        }
    }

    /// Collapses every duplicate in the store. Safe to call repeatedly — a second
    /// pass finds only groups of one and saves nothing.
    static func mergeAll(from library: IngredientLibrary = .bundled, in context: ModelContext) throws {
        var losers: [any PersistentModel] = []
        losers += try collapse(IngredientCategory.self, in: context)
        losers += try collapse(Provider.self, in: context)
        losers += try collapse(StorageLocation.self, in: context)
        losers += try collapse(RecipeCollection.self, in: context)
        losers += try collapseIngredients(from: library, in: context)
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

    /// Groups by `mergeKey`, keeps the lowest `uuid` of each group, and hands
    /// everything else to `adopt`. Returns the losers, still undeleted.
    private static func collapse<T: MergeableLookup>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> [T] {
        try collapse(context.fetch(FetchDescriptor<T>())).losers
    }

    /// The grouping itself, over rows already fetched, so a caller that needs the
    /// survivors as well as the losers doesn't have to fetch twice.
    private static func collapse<T: MergeableLookup>(
        _ all: [T]
    ) -> (winners: [String: T], losers: [T]) {
        var winners: [String: T] = [:]
        var losers: [T] = []

        let keyed = all.compactMap { model in model.mergeKey.map { (key: $0, model: model) } }
        for (key, group) in Dictionary(grouping: keyed, by: \.key) {
            let ordered = group.map(\.model).sorted { $0.uuid.uuidString < $1.uuid.uuidString }
            guard let winner = ordered.first else { continue }
            winners[key] = winner
            for loser in ordered.dropFirst() {
                T.adopt(loser, into: winner)
                losers.append(loser)
            }
        }
        return (winners, losers)
    }

    /// Ingredients take two passes over one fetch. The slug pass collapses the
    /// copies the library installer inevitably creates; the name pass then folds
    /// in rows that predate the library, which carry no slug and would otherwise
    /// sit beside their installed twin for good.
    ///
    /// Order matters: the name pass has to adopt into the slug pass's survivor,
    /// not into a row that is about to be deleted.
    private static func collapseIngredients(
        from library: IngredientLibrary,
        in context: ModelContext
    ) throws -> [Ingredient] {
        let all = try context.fetch(FetchDescriptor<Ingredient>())
        let (installed, losers) = collapse(all)
        return losers + adoptUnlinked(all.filter { $0.librarySlug.isEmpty }, from: library, into: installed)
    }

    /// Folds a slug-less ingredient into the installed library row whose entry
    /// claims its name or one of its aliases. The library row always wins, and
    /// the user's own chemistry survives on it as custom when it differs.
    ///
    /// This is the case the installer structurally cannot reach: it can only
    /// adopt rows already on the device when it runs, so a pre-library "Olive
    /// Oil" arriving from an older device after the slug is installed is never
    /// claimed by it.
    ///
    /// Two devices on different app versions can carry different alias lists, so
    /// a newer one may fold a pair an older one leaves alone. That still
    /// converges — the repoint and the tombstone sync over, and the older device
    /// simply never acts.
    ///
    /// Ingredients the user created that match no entry are never merged, even
    /// when two of them share a name: unlike a category, an ingredient carries
    /// purchases and batch history, and two things the user happened to name
    /// alike are not safe to fuse behind their back. See SW-140.
    private static func adoptUnlinked(
        _ unlinked: [Ingredient],
        from library: IngredientLibrary,
        into installed: [String: Ingredient]
    ) -> [Ingredient] {
        guard !unlinked.isEmpty else { return [] }

        var entries: [String: IngredientLibraryEntry] = [:]
        for entry in library.entries {
            for name in [entry.name] + entry.aliases {
                let key = name.lookupKey
                if !key.isEmpty, entries[key] == nil {
                    entries[key] = entry
                }
            }
        }

        var losers: [Ingredient] = []
        for ingredient in unlinked {
            let key = ingredient.name.lookupKey
            guard !key.isEmpty,
                  let entry = entries[key],
                  let winner = installed[entry.slug] else { continue }
            // Read against the catalog, not against the winner: what makes this
            // row's chemistry custom is that it differs from what SoapWiz ships.
            ingredient.hasCustomChemistry = !entry.hasSameChemistry(as: ingredient)
            Ingredient.adopt(ingredient, into: winner)
            losers.append(ingredient)
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
    /// device, and it survives the user renaming the row. A user-created
    /// ingredient has no slug and opts out.
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
