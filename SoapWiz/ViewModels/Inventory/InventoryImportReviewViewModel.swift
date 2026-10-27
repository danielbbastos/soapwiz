import Foundation
import SwiftData

/// A row the review screen can't offer for import, with the ingredient it
/// landed on so the user can tell which one it is.
struct InventoryImportBlockedLine: Identifiable {
    let line: InventoryImportLine
    /// `nil` for a row with no name, which landed on no ingredient.
    let entry: InventoryImportEntry?
    /// Set on the first blocked row of an ingredient that has no importable
    /// row, and so is listed nowhere else, when another match could help: the
    /// user re-pointed it, which must stay undoable, or a row is blocked only by
    /// where it was placed (a unit the ingredient can't take) and not by
    /// anything in the row itself. An ingredient that still has an importable
    /// row has these actions on its own entry row, and is offered them once
    /// rather than twice. Unnamed rows never have them.
    let offersMatchActions: Bool

    var id: UUID { line.id }

    var entryName: String? { entry?.name }
}

/// Edits an `InventoryImportPlan` for the review screen and carries it out.
///
/// Source-agnostic: it takes a plan, never a file, so the spreadsheet import
/// and a later invoice import share the screen.
///
/// Confirming never reports success for nothing. A plan with no importable row
/// has a `confirmBlocker` instead, and a save that fails or imports no row
/// leaves `errorMessage` and no `result`.
@MainActor
@Observable
final class InventoryImportReviewViewModel {
    private(set) var plan: InventoryImportPlan
    /// Set once, by a confirm that imported at least one row.
    private(set) var result: InventoryImportResult?
    private(set) var errorMessage: String?

    init(plan: InventoryImportPlan) {
        self.plan = plan
    }

    // MARK: - Sections

    /// Entries matched to the inventory that still have a row to import. One
    /// whose rows are all blocked is listed under "Can't import" alone.
    var matchedEntries: [InventoryImportEntry] {
        plan.entries.filter { !$0.isNew && hasImportableLine($0) }
    }

    var newEntries: [InventoryImportEntry] {
        plan.entries.filter { $0.isNew && hasImportableLine($0) }
    }

    var blockedLines: [InventoryImportBlockedLine] {
        let fromEntries = plan.entries.flatMap { entry in
            let offersActions = !hasImportableLine(entry) && (entry.isRematched || entry.lines.contains(where: isBlockedByPlacement))
            return entry.lines.filter { !$0.isImportable }.enumerated().map { index, line in
                InventoryImportBlockedLine(line: line, entry: entry, offersMatchActions: index == 0 && offersActions)
            }
        }
        return fromEntries + plan.unnamed.map { InventoryImportBlockedLine(line: $0, entry: nil, offersMatchActions: false) }
    }

    var importableCount: Int { plan.importableCount }
    var skippedCount: Int { plan.skippedCount }

    /// Whether every row of the entry that can be imported is switched on.
    func isIncluded(_ entry: InventoryImportEntry) -> Bool {
        let importable = entry.lines.filter(\.isImportable)
        return !importable.isEmpty && importable.allSatisfy(\.isIncluded)
    }

    func canResetToNew(_ entry: InventoryImportEntry) -> Bool {
        entry.startedAsNew && entry.isRematched
    }

    func canResetMatch(_ entry: InventoryImportEntry) -> Bool {
        !entry.startedAsNew && entry.isRematched
    }

    // MARK: - Edits

    func setIncluded(_ included: Bool, line id: UUID) {
        plan.setIncluded(included, forLine: id)
    }

    func setIncluded(_ included: Bool, entry id: UUID) {
        plan.setIncluded(included, forEntry: id)
    }

    func rematch(entry id: UUID, to ingredient: Ingredient) {
        plan.rematch(entry: id, to: ingredient)
    }

    func resetMatch(entry id: UUID) {
        plan.resetMatch(entry: id)
    }

    func setCategory(_ name: String?, entry id: UUID) {
        plan.setCategory(name, forEntry: id)
    }

    // MARK: - Entered amounts

    func canEnterAmount(_ line: InventoryImportLine) -> Bool {
        line.canEnterQuantity
    }

    /// The amount `text` holds, or `nil` unless it is a positive number, so the
    /// field's confirm button and `enterAmount` agree on what is acceptable.
    func parsedAmount(_ text: String) -> Double? {
        guard let amount = LocaleDecimal.parse(text), amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    /// What the file said, shown beside the field so the user can work their
    /// own amount out from it.
    func fileQuantityNote(_ line: InventoryImportLine) -> String? {
        guard let quantity = line.row.quantity, let unit = line.row.unit else { return nil }
        let formatted = InventoryImportIssue.fileQuantityText(quantity)
        return String(localized: "The file says \(formatted) \(unit.rawValue).")
    }

    /// Imports the row with the typed amount, in the ingredient's unit. Text
    /// that isn't a positive number changes nothing.
    func enterAmount(_ text: String, line id: UUID) {
        guard let amount = parsedAmount(text) else { return }
        plan.enterQuantity(amount, forLine: id)
    }

    func clearEnteredAmount(line id: UUID) {
        plan.clearEnteredQuantity(forLine: id)
    }

    // MARK: - Category

    /// The category a new ingredient will be filed under; `nil` is Others,
    /// whether the file said so or said nothing.
    func categoryName(of entry: InventoryImportEntry) -> String? {
        guard case .newIngredient(let new) = entry.resolution,
              let name = new.categoryName,
              name.lookupKey != IngredientCategory.Name.others.lookupKey else { return nil }
        return name
    }

    /// The categories a new ingredient can be filed under besides Others: the
    /// ones that exist, and the one the file named when none of them is it.
    func categoryOptions(for entry: InventoryImportEntry, existing: [String]) -> [String] {
        var fromFile: [String] = []
        if case .newIngredient(let new) = entry.originalResolution, let name = new.categoryName {
            fromFile.append(name)
        }
        var seen: Set<String> = [IngredientCategory.Name.others.lookupKey]
        return (existing + fromFile).filter { seen.insert($0.lookupKey).inserted }
    }

    // MARK: - Confirm

    /// Why there is nothing to import, or `nil` when there is.
    var confirmBlocker: String? {
        guard importableCount == 0 else { return nil }
        if plan.entries.contains(where: hasImportableLine) {
            return String(localized: "Every row is turned off. Turn on at least one to import.")
        }
        return String(localized: "None of these rows can be imported. Check the reasons under Can't Import.")
    }

    var canConfirm: Bool { confirmBlocker == nil && result == nil }

    func confirm(in context: ModelContext) {
        guard canConfirm else { return }
        errorMessage = nil
        do {
            let applied = try InventoryImportApplier.apply(plan, in: context)
            // The applier skips a match that was merged away since the plan was
            // made, so a plan that looked importable can still add nothing.
            guard applied.importedRows > 0 else {
                errorMessage = String(localized: "Nothing was imported. The ingredients these rows matched may have changed.")
                return
            }
            result = applied
        } catch {
            errorMessage = String(localized: "The import couldn't be saved. Nothing was changed.")
        }
    }

    /// For the screen that follows the review.
    var resultSummary: String? {
        guard let result else { return nil }
        let imported = result.importedRows
        let skipped = result.skippedRows
        return imported == 1
            ? String(localized: "Imported 1 row, skipped \(skipped)")
            : String(localized: "Imported \(imported) rows, skipped \(skipped)")
    }

    // MARK: - Helpers

    private func isBlockedByPlacement(_ line: InventoryImportLine) -> Bool {
        !line.rowIssues.contains(where: \.isBlocking) && line.placementIssues.contains(where: \.isBlocking)
    }

    private func hasImportableLine(_ entry: InventoryImportEntry) -> Bool {
        entry.lines.contains(where: \.isImportable)
    }
}
