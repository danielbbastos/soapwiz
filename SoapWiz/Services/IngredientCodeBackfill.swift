import Foundation
import OSLog
import SwiftData

/// Gives every library ingredient its journal `code` after the update that
/// shipped codes with the library.
///
/// The installer only ever touches rows it *adds*, so an install that predates
/// SW-156 keeps its library rows with an empty `code` — and an empty code makes
/// `PurchaseFormViewModel.suggestedJournalCode(for:)` open every purchase with a
/// blank journal field. This pass fills the blanks from the bundled entry,
/// leaving a code the user typed alone, and never lets two rows share one.
///
/// Only rows carrying a `librarySlug` and an empty `code` are touched, so a
/// user's own ingredients and any code they set are untouched, and a second
/// pass writes nothing.
@MainActor
enum IngredientCodeBackfill {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "backfill")

    /// Runs the pass and swallows a failure, having logged it. A missing journal
    /// code only weakens a suggestion, which is survivable; losing the launch to
    /// it would not be.
    static func fillMissingCodesLoggingFailure(
        from library: IngredientLibrary = .bundled,
        in context: ModelContext
    ) {
        do {
            try fillMissingCodes(from: library, in: context)
        } catch {
            log.error("Ingredient code backfill failed: \(error, privacy: .public)")
        }
    }

    /// Fills the code on every library row that has none, and returns how many
    /// were filled.
    @discardableResult
    static func fillMissingCodes(from library: IngredientLibrary, in context: ModelContext) throws -> Int {
        let entriesBySlug = Dictionary(
            library.entries.map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        var usedCodes = Set(ingredients.compactMap { $0.code.isEmpty ? nil : $0.code.uppercased() })
        var filled = 0

        for ingredient in ingredients where ingredient.code.isEmpty && !ingredient.librarySlug.isEmpty {
            guard let entry = entriesBySlug[ingredient.librarySlug] else { continue }
            let code = IngredientCodeSuggester.installCode(for: entry, usedCodes: usedCodes)
            guard !code.isEmpty else { continue }
            ingredient.code = code
            usedCodes.insert(code.uppercased())
            filled += 1
        }

        guard filled > 0 else { return 0 }
        try context.save()
        log.notice("Filled \(filled, privacy: .public) missing ingredient code(s).")
        return filled
    }
}
