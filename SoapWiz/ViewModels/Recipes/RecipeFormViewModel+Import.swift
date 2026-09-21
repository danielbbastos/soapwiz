import Foundation
import SwiftData

/// The names one source used for a single ingredient, in the order it wrote them.
///
/// Kept so the description can name *every* name that went into a merged amount.
/// Naming only the ingredient would report "Olive Oil" and leave the user with no
/// way to tell which other line was folded into it.
private struct ImportedNameGroup {
    let id: PersistentIdentifier
    var names: [String]
}

/// What an import row is, relative to the rows already applied in its section.
/// See `ImportedNameLedger.kind(of:resolving:)`.
private enum ImportRowKind {
    /// This ingredient hasn't been applied yet.
    case first

    /// The same ingredient under a different written name: a second real entry,
    /// whose amount belongs with the first.
    case merged

    /// The same ingredient under the same written name: one entry read twice.
    case repeated
}

/// What one section of an import has applied so far: which ingredient each row
/// resolved to, and the names the source wrote for it.
///
/// A source can put one ingredient on two lines in two different ways, and they
/// call for opposite answers.
///
/// Two *different* names the catalog resolves to one ingredient — "Olive Oil -
/// All Grades" and "Sweet Oil", which is an old name for the same oil — are two
/// real entries. The recipe wants both amounts, and dropping either loses a
/// quantity the user wrote down. Alias resolution is what made this common.
///
/// The *same* name twice — a summary line above the table, or one line OCR reads
/// from both a sticky header and the body — is one entry seen twice. Adding those
/// would turn a re-read "Olive Oil 55%" into 110%, worse than either answer.
///
/// The written name is what tells them apart, so it decides. The user is told
/// which happened either way.
///
/// One ledger per section, never shared: the three sections keep separate drafts,
/// so an ingredient used as both an oil and an additive is two rows rather than a
/// repeat of one.
private struct ImportedNameLedger {
    private var groups: [ImportedNameGroup] = []

    func kind(of row: RecipeImportRow, resolving ingredient: Ingredient) -> ImportRowKind {
        let key = row.imported.name.lookupKey
        guard let group = groups.first(where: { $0.id == ingredient.persistentModelID }) else {
            return .first
        }
        return group.names.contains { $0.lookupKey == key } ? .repeated : .merged
    }

    /// Records the name this row was written under. Called only once a row's amount
    /// has actually been applied, so a row held back — an additive in a unit that
    /// can't be added — is never reported as having been merged.
    mutating func record(_ row: RecipeImportRow, for ingredient: Ingredient) {
        let written = row.imported.name.trimmingCharacters(in: .whitespaces)
        let id = ingredient.persistentModelID
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            groups.append(ImportedNameGroup(id: id, names: [written]))
            return
        }
        groups[index].names.append(written)
    }

    /// The groups that ended up holding more than one name — the merges.
    var merges: [[String]] {
        groups.filter { $0.names.count > 1 }.map(\.names)
    }
}

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
        var merged: [[String]] = []
        applyOils(prepared.rows(for: .oil), repeated: &repeated, merged: &merged)
        applyAdditives(prepared.rows(for: .additive), repeated: &repeated, merged: &merged)
        applyFragrances(prepared.rows(for: .fragrance), repeated: &repeated, merged: &merged)

        desc = importedDescription(for: prepared, repeated: repeated, merged: merged)
    }

    private func oilDraft(for ingredient: Ingredient) -> OilIngredientDraft? {
        oilDrafts.last { $0.ingredient.persistentModelID == ingredient.persistentModelID }
    }

    private func additiveDraft(for ingredient: Ingredient) -> IngredientAmountDraft? {
        additiveDrafts.last { $0.ingredient.persistentModelID == ingredient.persistentModelID }
    }

    private func fragranceDraft(for ingredient: Ingredient) -> IngredientAmountDraft? {
        fragranceDrafts.last { $0.ingredient.persistentModelID == ingredient.persistentModelID }
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
        if let lyeType = draft.lyeType { setLyeType(lyeType) }
        if let superFat = draft.superFat { self.superFat = superFat }
        if let waterParts = draft.waterParts { self.waterParts = waterParts }
        if let fragrancePercentage = draft.fragrancePercentage {
            self.fragrancePercentage = fragrancePercentage
        }
        if let cfmNeutralizer = draft.cfmNeutralizer {
            useCFM = true
            self.cfmNeutralizer = cfmNeutralizer
        }
    }

    private func importedDescription(
        for prepared: PreparedRecipeImport,
        repeated: [String],
        merged: [[String]]
    ) -> String {
        var notes: [String] = []
        let skipped = prepared.skippedDescriptions
        if !skipped.isEmpty {
            notes.append("Not imported: \(skipped.joined(separator: ", "))")
        }
        if !merged.isEmpty {
            // Every name the source used, not just the ingredient's own: "Olive
            // Oil" alone would leave the user unable to tell which other line was
            // folded into it. Groups are separated by a semicolon so two merges
            // can't read as one long list.
            let phrases = merged.map { $0.formatted() }
            notes.append("Named more than once and added together: \(phrases.joined(separator: "; "))")
        }
        if !repeated.isEmpty {
            notes.append("Repeated in the source, kept once: \(repeated.joined(separator: ", "))")
        }
        return ([prepared.draft.desc] + notes)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Ingredient rows

    private func applyOils(_ rows: [RecipeImportRow], repeated: inout [String], merged: inout [[String]]) {
        var ledger = ImportedNameLedger()
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            switch ledger.kind(of: row, resolving: ingredient) {
            case .repeated:
                repeated.append(ingredient.name)
            case .first:
                addOil(ingredient)
                guard let draft = oilDraft(for: ingredient) else { continue }
                ledger.record(row, for: ingredient)
                userEdited(id: draft.id, amount: row.imported.amount)
            case .merged:
                guard let draft = oilDraft(for: ingredient) else { continue }
                ledger.record(row, for: ingredient)
                // `userEdited` assigns rather than adds, so the total is worked out
                // here and written once.
                userEdited(id: draft.id, amount: draft.amount + row.imported.amount)
            }
        }
        merged.append(contentsOf: ledger.merges)
    }

    private func applyAdditives(_ rows: [RecipeImportRow], repeated: inout [String], merged: inout [[String]]) {
        var ledger = ImportedNameLedger()
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            let unit = resolvedUnit(row.imported.unit, among: RecipeUnitOptions.additive, fallback: defaultAdditiveUnit)
            switch ledger.kind(of: row, resolving: ingredient) {
            case .repeated:
                repeated.append(ingredient.name)
            case .first:
                addAdditive(ingredient)
                guard let draft = additiveDraft(for: ingredient) else { continue }
                ledger.record(row, for: ingredient)
                updateAdditive(id: draft.id, amount: row.imported.amount, unit: unit)
            case .merged:
                guard let draft = additiveDraft(for: ingredient) else { continue }
                // Only amounts in the same unit can be added. "15 g" and "2% of
                // oils" describe different quantities, and summing the numbers
                // would invent a third that is neither. A mismatch keeps the first
                // amount, which is what a repeat does, and is reported as one —
                // and is deliberately not recorded as a merge.
                guard draft.unit == unit else {
                    repeated.append(ingredient.name)
                    continue
                }
                ledger.record(row, for: ingredient)
                updateAdditive(id: draft.id, amount: draft.amount + row.imported.amount, unit: unit)
            }
        }
        merged.append(contentsOf: ledger.merges)
    }

    /// The recipe-wide fragrance unit is adopted from the first applied row —
    /// the unit is one per recipe now, so later rows written in something else
    /// are read as amounts in the adopted unit. With the unit settled up front,
    /// each row is added and given its amount in one pass; the amounts lock
    /// their rows as they go, so a later row can't redistribute an earlier one
    /// away.
    private func applyFragrances(_ rows: [RecipeImportRow], repeated: inout [String], merged: inout [[String]]) {
        var ledger = ImportedNameLedger()
        var unitAdopted = false
        for row in rows {
            guard let ingredient = row.ingredient else { continue }
            // `if case` rather than the `switch` the other two sections use: the
            // recipe-wide unit has to be adopted between rejecting a repeat and
            // handling the other two cases, and a `switch` would have to repeat that
            // step inside both remaining branches.
            let rowKind = ledger.kind(of: row, resolving: ingredient)
            if case .repeated = rowKind {
                repeated.append(ingredient.name)
                continue
            }
            if !unitAdopted {
                unitAdopted = true
                // The kind's own units, not every unit that exists. `% of batch`
                // and `% of liquids` resolve against the lye and the water, which
                // a general recipe has none of: adopting one there doesn't merely
                // read oddly, it makes the row resolve to nothing, drop out of
                // the cost breakdown, and never be deducted at batch creation —
                // a fragrance the recipe lists and the batch silently doesn't
                // consume. See SW-121.
                let options = availableFragranceUnits.map(\.rawValue)
                let fallback = importedFragranceUnitFallback.rawValue
                let unit = resolvedUnit(row.imported.unit, among: options, fallback: fallback)
                setFragranceUnit(FragranceUnit.resolve(unit))
            }
            // Every row is entered in the one recipe-wide unit adopted above, so
            // two rows for the same fragrance are always directly addable.
            if case .merged = rowKind {
                guard let draft = fragranceDraft(for: ingredient) else { continue }
                ledger.record(row, for: ingredient)
                userEditedFragrance(id: draft.id, amount: draft.amount + row.imported.amount)
                continue
            }
            addFragrance(ingredient)
            guard let draft = fragranceDraft(for: ingredient) else { continue }
            ledger.record(row, for: ingredient)
            userEditedFragrance(id: draft.id, amount: row.imported.amount)
        }
        merged.append(contentsOf: ledger.merges)
    }

    /// What an imported fragrance falls back to when the source states a unit
    /// the form can't offer, or none at all.
    ///
    /// Deliberately not the form's own default of shares-of-the-blend: an
    /// imported recipe is describing quantities, and "Lavender 3" in a recipe
    /// written in ounces means three ounces, not three shares. So a percentage
    /// recipe reads it against the oils and a weight recipe reads it as a
    /// weight, which is what the source most likely meant.
    private var importedFragranceUnitFallback: FragranceUnit {
        weightUnitIsPercentage ? .percentOfOils : FragranceUnit(rawValue: weightUnit) ?? .grams
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
