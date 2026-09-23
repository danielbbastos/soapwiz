import Foundation
import OSLog
import SwiftData

/// Puts the bundled `IngredientLibrary` into the store, so a fresh install opens
/// on a full inventory the user can add purchases to straight away.
///
/// Runs on every launch and only ever adds what is missing, which is also how an
/// app update delivers new entries. An entry counts as present once any
/// ingredient carries its slug — hidden or customised included — so nothing the
/// user has changed is ever put back beside itself.
///
/// Ingredients created before the library existed are adopted rather than
/// duplicated: a user-created row whose name matches an entry takes its slug,
/// and keeps its own chemistry, flagged as custom, when that differs.
///
/// Every device installs its own rows before sync delivers the others, so a
/// second device briefly holds two of each. Collapsing those is a merge after
/// sync, not this pass's job.
@MainActor
enum IngredientLibraryInstaller {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "library")

    /// Runs the install and swallows a failure, having logged it. An incomplete
    /// library is survivable — the next launch tries again. Losing the launch to
    /// it would not be.
    static func installMissingLoggingFailure(
        from library: IngredientLibrary = .bundled,
        in context: ModelContext
    ) {
        do {
            try installMissing(from: library, in: context)
        } catch {
            log.error("Ingredient library install failed: \(error, privacy: .public)")
        }
    }

    /// Adds the categories and ingredients the store is missing, and returns how
    /// many rows were inserted or adopted.
    @discardableResult
    static func installMissing(from library: IngredientLibrary, in context: ModelContext) throws -> Int {
        var changes = 0
        var categories = try categoryIndex(in: context, changes: &changes)

        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        var installed = Set(ingredients.map(\.librarySlug).filter { !$0.isEmpty })
        var usedCodes = Set(ingredients.compactMap { $0.code.isEmpty ? nil : $0.code.uppercased() })
        var unlinked: [String: Ingredient] = [:]
        for ingredient in ingredients where ingredient.librarySlug.isEmpty {
            let key = ingredient.name.lookupKey
            if !key.isEmpty, unlinked[key] == nil {
                unlinked[key] = ingredient
            }
        }

        for entry in library.entries where installed.insert(entry.slug).inserted {
            if let existing = takeAdoptable(for: entry, from: &unlinked) {
                if existing.category == nil {
                    existing.category = category(named: entry.category, in: &categories, context: context, changes: &changes)
                }
                adopt(existing, into: entry, usedCodes: &usedCodes)
            } else {
                let entryCategory = category(named: entry.category, in: &categories, context: context, changes: &changes)
                context.insert(makeIngredient(from: entry, category: entryCategory, usedCodes: &usedCodes))
            }
            changes += 1
        }

        guard changes > 0 else { return 0 }
        try context.save()
        log.notice("Installed \(changes, privacy: .public) ingredient library change(s).")
        return changes
    }

    /// Existing categories keyed by lookup key. A store with none at all — a
    /// fresh install — starts with every default category. After that, deleting
    /// or renaming one is the user's decision, and this pass never undoes it.
    private static func categoryIndex(
        in context: ModelContext,
        changes: inout Int
    ) throws -> [String: IngredientCategory] {
        let existing = try context.fetch(FetchDescriptor<IngredientCategory>())
        var index: [String: IngredientCategory] = [:]
        for category in existing where index[category.name.lookupKey] == nil {
            index[category.name.lookupKey] = category
        }
        guard existing.isEmpty else { return index }

        for name in IngredientCategory.Name.all {
            let category = IngredientCategory(name: name)
            context.insert(category)
            index[name.lookupKey] = category
            changes += 1
        }
        return index
    }

    /// The category an entry's ingredient belongs in, created only when an
    /// ingredient actually needs one the store no longer has.
    private static func category(
        named name: String,
        in index: inout [String: IngredientCategory],
        context: ModelContext,
        changes: inout Int
    ) -> IngredientCategory? {
        let key = name.lookupKey
        guard !key.isEmpty else { return nil }
        if let existing = index[key] {
            return existing
        }
        let category = IngredientCategory(name: name)
        context.insert(category)
        index[key] = category
        changes += 1
        return category
    }

    /// Removes and returns the user-created ingredient the entry should adopt, so
    /// no two entries can claim the same row.
    private static func takeAdoptable(
        for entry: IngredientLibraryEntry,
        from unlinked: inout [String: Ingredient]
    ) -> Ingredient? {
        for key in entry.lookupNames {
            if let ingredient = unlinked.removeValue(forKey: key) {
                return ingredient
            }
        }
        return nil
    }

    /// The user's own name, unit, purchases and category stay. A row that never
    /// had a code takes the entry's; one the user already coded keeps it, so the
    /// journal numbers already in use never shift.
    private static func adopt(
        _ ingredient: Ingredient,
        into entry: IngredientLibraryEntry,
        usedCodes: inout Set<String>
    ) {
        ingredient.librarySlug = entry.slug
        ingredient.hasCustomChemistry = !entry.hasSameChemistry(as: ingredient)
        guard ingredient.code.isEmpty else { return }
        ingredient.code = takeCode(for: entry, usedCodes: &usedCodes)
    }

    private static func makeIngredient(
        from entry: IngredientLibraryEntry,
        category: IngredientCategory?,
        usedCodes: inout Set<String>
    ) -> Ingredient {
        let ingredient = Ingredient(name: entry.name, category: category, unit: entry.unit)
        ingredient.librarySlug = entry.slug
        ingredient.code = takeCode(for: entry, usedCodes: &usedCodes)
        ingredient.sapValue = entry.sapValue
        ingredient.kohSapValue = entry.kohSapValue
        ingredient.density = entry.density
        ingredient.fattyAcidProfile = entry.fattyAcidProfile
        return ingredient
    }

    /// Resolves the entry's code against the codes already claimed and records
    /// the result so no two rows in one pass share one.
    private static func takeCode(
        for entry: IngredientLibraryEntry,
        usedCodes: inout Set<String>
    ) -> String {
        let code = IngredientCodeSuggester.installCode(for: entry, usedCodes: usedCodes)
        if !code.isEmpty { usedCodes.insert(code.uppercased()) }
        return code
    }
}
