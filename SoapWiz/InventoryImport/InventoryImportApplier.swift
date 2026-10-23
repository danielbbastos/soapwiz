import Foundation
import SwiftData

struct InventoryImportResult: Equatable {
    var importedRows = 0
    var skippedRows = 0
    var ingredientsCreated = 0
    var purchasesAdded = 0
}

/// Writes an `InventoryImportPlan` into the store.
///
/// Unlike `RecipeTransferImporter`, whose caller saves, the applier owns the
/// save: an import is a single user action, and one that fails halfway must
/// leave nothing behind, so any error rolls the context back before it is
/// rethrown.
///
/// A plan with no included rows writes nothing and returns a result that says
/// so, rather than throwing; the screen decides how to tell the user.
@MainActor
enum InventoryImportApplier {
    static func apply(_ plan: InventoryImportPlan, in context: ModelContext) throws -> InventoryImportResult {
        guard plan.importableCount > 0 else {
            return InventoryImportResult(skippedRows: plan.rowCount)
        }
        do {
            var session = try Session(context: context)
            var result = InventoryImportResult()
            for entry in plan.entries {
                session.apply(entry, to: &result)
            }
            result.skippedRows = plan.rowCount - result.importedRows
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    /// The lookups one import shares, so that two rows naming one new category,
    /// provider or code resolve to the same row instead of each making their own.
    private struct Session {
        let context: ModelContext
        let now = Date.now
        var categories: [String: IngredientCategory] = [:]
        var providers: [String: Provider] = [:]
        var usedCodes: Set<String> = []

        init(context: ModelContext) throws {
            self.context = context
            for category in try context.fetch(FetchDescriptor<IngredientCategory>()) where categories[category.name.lookupKey] == nil {
                categories[category.name.lookupKey] = category
            }
            for provider in try context.fetch(FetchDescriptor<Provider>()) where providers[provider.name.lookupKey] == nil {
                providers[provider.name.lookupKey] = provider
            }
            let codes = try context.fetch(FetchDescriptor<Ingredient>()).map(\.code)
            usedCodes = Set(codes.filter { !$0.isEmpty }.map { $0.uppercased() })
        }

        mutating func apply(_ entry: InventoryImportEntry, to result: inout InventoryImportResult) {
            let lines = entry.lines.filter(\.isIncluded)
            guard !lines.isEmpty else { return }

            var rows = lines.map { (row: $0.row, quantity: $0.quantity) }
            let ingredient: Ingredient
            switch entry.resolution {
            case .existing(let match):
                // The row may have been merged away since the plan was made.
                guard let live = LiveIngredient.resolve(match.ingredient, slug: match.slug, in: context) else { return }
                ingredient = live
                // The plan converted each quantity into the matched copy's unit.
                // A survivor can have a different unit or density, so the rows
                // are placed again on it, and one it can't take is skipped.
                if live !== match.ingredient {
                    rows = rows.compactMap { row in
                        let placement = InventoryImportMatcher.place(row.row, unit: live.unit, density: live.density, isExisting: true)
                        guard !placement.issues.contains(where: \.isBlocking) else { return nil }
                        return (row.row, placement.quantity)
                    }
                }
            case .newIngredient(let new):
                ingredient = makeIngredient(new)
                result.ingredientsCreated += 1
            }

            for row in rows {
                result.importedRows += 1
                guard let quantity = row.quantity else { continue }
                addPurchase(for: row.row, quantity: quantity, to: ingredient)
                result.purchasesAdded += 1
            }
        }

        private mutating func makeIngredient(_ new: InventoryImportNewIngredient) -> Ingredient {
            let category = category(named: new.categoryName ?? IngredientCategory.Name.others)
            let ingredient = Ingredient(name: new.name, category: category, unit: new.unit.rawValue)
            if let entry = new.libraryEntry {
                ingredient.librarySlug = entry.slug
                ingredient.sapValue = entry.sapValue
                ingredient.kohSapValue = entry.kohSapValue
                ingredient.density = entry.density
                ingredient.fattyAcidProfile = entry.fattyAcidProfile
                ingredient.code = IngredientCodeSuggester.installCode(for: entry, usedCodes: usedCodes)
            } else {
                let suggested = IngredientCodeSuggester.suggest(for: new.name, existingCodes: Array(usedCodes))
                ingredient.code = usedCodes.contains(suggested.uppercased()) ? "" : suggested
            }
            if !ingredient.code.isEmpty { usedCodes.insert(ingredient.code.uppercased()) }
            context.insert(ingredient)
            return ingredient
        }

        /// The journal code is worked out before the purchase is attached, from
        /// the purchases the pass has already added, so one import continues the
        /// ingredient's sequence instead of numbering every row alike.
        private mutating func addPurchase(for row: InventoryImportRow, quantity: Double, to ingredient: Ingredient) {
            let purchase = IngredientPurchase(
                provider: provider(named: row.supplier),
                dateOfPurchase: row.purchaseDate ?? now,
                quantity: quantity,
                totalPrice: row.totalPrice ?? 0,
                badge: "",
                journalCode: PurchaseFormViewModel.suggestedJournalCode(for: ingredient),
                expiryDate: row.expiryDate,
                openingDate: nil
            )
            context.insert(purchase)
            purchase.attach(to: ingredient)
        }

        private mutating func category(named name: String) -> IngredientCategory {
            let key = name.lookupKey
            if let existing = categories[key] { return existing }
            let category = IngredientCategory(name: name)
            context.insert(category)
            categories[key] = category
            return category
        }

        private mutating func provider(named name: String?) -> Provider? {
            guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            let key = trimmed.lookupKey
            if let existing = providers[key] { return existing }
            let provider = Provider(name: trimmed)
            context.insert(provider)
            providers[key] = provider
            return provider
        }
    }
}
