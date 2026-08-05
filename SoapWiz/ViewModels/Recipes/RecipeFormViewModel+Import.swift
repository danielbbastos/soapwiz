import Foundation
import SwiftData

/// Applying a reviewed import to the recipe form.
///
/// The form is filled in but nothing is saved: the user still lands on the
/// normal recipe screen, can check the Stats tab, and has to press Save. That
/// keeps a misread percentage catchable, and it means an abandoned import
/// leaves no trace in the store.
extension RecipeFormViewModel {
    func applyImport(_ prepared: PreparedRecipeImport) {
        guard !hasImported else { return }
        hasImported = true

        let draft = prepared.draft
        name = draft.name
        applyWeightMode(from: draft)
        applyLyeSettings(from: draft)

        var repeated: [String] = []
        applyOils(prepared.rows(for: .oil), repeated: &repeated)
        applyAdditives(prepared.rows(for: .additive), repeated: &repeated)
        applyFragrances(prepared.rows(for: .fragrance), repeated: &repeated)

        desc = importedDescription(for: prepared, repeated: repeated)
    }

    /// Whether a row's ingredient has already had its amount applied in this
    /// section, recording the repeat if so.
    ///
    /// A source can name the same ingredient twice — a summary above the table,
    /// or a line OCR reads from both a sticky header and the body. The form
    /// holds one row per ingredient, so without this the second amount silently
    /// replaced the first and changed the recipe's proportions.
    ///
    /// The first amount wins rather than the two being added. A repeat is far
    /// more often the same information twice than a deliberate split, and
    /// summing a re-read "Olive Oil 55%" into 110% would be a worse answer than
    /// either. The user is told either way.
    private func isRepeat(
        _ row: RecipeImportRow,
        of ingredient: Ingredient,
        seen: inout Set<PersistentIdentifier>,
        repeated: inout [String]
    ) -> Bool {
        guard !seen.insert(ingredient.persistentModelID).inserted else { return false }
        repeated.append(ingredient.name)
        return true
    }

    // MARK: - Configuration

    /// A recipe written in percentages keeps its percentages, with the batch
    /// size going into `totalOilWeight`. One written in weights is measured in
    /// the source's own unit, which is what `weightUnit` means outside
    /// percentage mode.
    private func applyWeightMode(from draft: RecipeImportDraft) {
        if draft.amountsArePercentages {
            weightUnit = "%"
            oilWeightUnit = draft.resolvedBatchUnit
            totalOilWeight = draft.batchSize ?? totalOilWeight
        } else {
            weightUnit = draft.resolvedBatchUnit
            oilWeightUnit = draft.resolvedBatchUnit
        }
    }

    /// Only values the source actually stated are applied. A recipe that says
    /// nothing about superfat keeps the form's default rather than being told
    /// it wants 0%.
    private func applyLyeSettings(from draft: RecipeImportDraft) {
        setLyeType(draft.lyeType)
        if let superFat = draft.superFat { self.superFat = superFat }
        if let waterParts = draft.waterParts { self.waterParts = waterParts }
        if let fragrancePercentage = draft.fragrancePercentage {
            self.fragrancePercentage = fragrancePercentage
        }
    }

    private func importedDescription(for prepared: PreparedRecipeImport, repeated: [String]) -> String {
        var notes: [String] = []
        let skipped = prepared.skippedDescriptions
        if !skipped.isEmpty {
            notes.append("Not imported: \(skipped.joined(separator: ", "))")
        }
        if !repeated.isEmpty {
            notes.append("Repeated in the source, kept once: \(repeated.joined(separator: ", "))")
        }
        return ([prepared.draft.desc] + notes)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Ingredient rows

    private func applyOils(_ rows: [RecipeImportRow], repeated: inout [String]) {
        var seen: Set<PersistentIdentifier> = []
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            guard !isRepeat(row, of: ingredient, seen: &seen, repeated: &repeated) else { continue }
            addOil(ingredient)
            guard let draft = oilDrafts.last(where: {
                $0.ingredient.persistentModelID == ingredient.persistentModelID
            }) else { continue }
            userEdited(id: draft.id, amount: row.imported.amount)
        }
    }

    private func applyAdditives(_ rows: [RecipeImportRow], repeated: inout [String]) {
        var seen: Set<PersistentIdentifier> = []
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            guard !isRepeat(row, of: ingredient, seen: &seen, repeated: &repeated) else { continue }
            addAdditive(ingredient)
            guard let draft = additiveDrafts.last(where: {
                $0.ingredient.persistentModelID == ingredient.persistentModelID
            }) else { continue }
            let unit = resolvedUnit(row.imported.unit, among: RecipeUnitOptions.additive, fallback: defaultAdditiveUnit)
            updateAdditive(id: draft.id, amount: row.imported.amount, unit: unit)
        }
    }

    /// The unit is set before the amount: `updateFragrance(unit:)` unlocks every
    /// fragrance row and redistributes, which would overwrite an amount set
    /// first. Setting the amount afterwards locks the row and makes it stick.
    private func applyFragrances(_ rows: [RecipeImportRow], repeated: inout [String]) {
        var seen: Set<PersistentIdentifier> = []
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            guard !isRepeat(row, of: ingredient, seen: &seen, repeated: &repeated) else { continue }
            addFragrance(ingredient)
            guard let draft = fragranceDrafts.last(where: {
                $0.ingredient.persistentModelID == ingredient.persistentModelID
            }) else { continue }
            let unit = resolvedUnit(row.imported.unit, among: RecipeUnitOptions.fragrance, fallback: defaultFragranceUnit)
            updateFragrance(id: draft.id, unit: unit)
            userEditedFragrance(id: draft.id, amount: row.imported.amount)
        }
    }

    /// Keeps the source's unit when the form can offer it, and falls back to the
    /// section default otherwise. A unit the pickers don't list would leave the
    /// row showing something the user can't reselect.
    private func resolvedUnit(_ imported: String?, among options: [String], fallback: String) -> String {
        guard let imported else { return fallback }
        let key = imported.trimmingCharacters(in: .whitespaces).lookupKey
        if let match = options.first(where: { $0.lookupKey == key }) { return match }
        if Self.meansPercentOfOils(key), let percentOfOils = options.first(where: { $0 == Self.percentOfOils }) {
            return percentOfOils
        }
        return fallback
    }

    /// Whether a written unit is a bare percentage.
    ///
    /// Sources write "3%" constantly; the pickers only offer the compound forms
    /// ("% of oils", "% of batch", "% of liquids"), so a bare percent matches
    /// nothing and would otherwise fall back to a *weight* — turning "Sodium
    /// Lactate 1%" into one gram, and "Fragrance 3%" in a weight-based recipe
    /// into three grams. That is a silent change of quantity, and for citric,
    /// lactic or ascorbic acid it feeds `LyeCalculator.acidNeutralization` and
    /// moves the lye weight with it.
    ///
    /// Oils is the base soap makers mean when they leave it unsaid, and it is
    /// what the form already defaults fragrance to in percentage mode. Reading
    /// it as a percentage of something is right in a way that reading it as a
    /// weight can never be.
    private static func meansPercentOfOils(_ key: String) -> Bool {
        ["%", "percent", "pct", "% of oil", "percent of oils", "% oils"].contains(key)
    }

    private static let percentOfOils = "% of oils"
}
