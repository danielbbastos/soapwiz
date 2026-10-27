import Foundation

/// Where a row's quantity ends up once it is in an ingredient's unit.
struct InventoryImportPlacement: Equatable {
    let quantity: Double?
    let issues: [InventoryImportIssue]
}

/// Decides, for each imported row, which ingredient it belongs to, and
/// converts its quantity into that ingredient's unit.
///
/// Matching is exact and nothing else, for the reason `RecipeIngredientReconciler`
/// gives: a fuzzy match would file stock under the wrong ingredient without
/// anything to show it. A row matches the inventory ingredient with the same
/// `String.lookupKey`, or failing that the installed row of the library entry
/// that ships under its name or an alias. Anything else becomes a new ingredient.
///
/// A match never changes the ingredient it finds; it only gets a purchase.
@MainActor
enum InventoryImportMatcher {
    static func plan(for rows: [InventoryImportRow], inventory: [Ingredient]) -> InventoryImportPlan {
        let index = IngredientIndex(inventory)
        var groups: [Group] = []
        var groupIndexByKey: [GroupKey: Int] = [:]
        var unnamed: [InventoryImportLine] = []

        for row in rows {
            let rowIssues = validationIssues(of: row)
            guard !row.name.lookupKey.isEmpty else {
                unnamed.append(InventoryImportLine(row: row, rowIssues: rowIssues, placement: .init(quantity: nil, issues: [])))
                continue
            }

            let target = target(for: row.name, in: index)
            let key = target.groupKey
            if let existing = groupIndexByKey[key] {
                groups[existing].rows.append((row, rowIssues))
            } else {
                groupIndexByKey[key] = groups.count
                groups.append(Group(target: target, rows: [(row, rowIssues)]))
            }
        }

        return InventoryImportPlan(entries: groups.map(entry(for:)), unnamed: unnamed)
    }

    /// Converts `row`'s quantity into `unit`, the unit of the ingredient it is
    /// going on, and reports what that took.
    ///
    /// A row with no unit is taken to be in the ingredient's own. The same kind
    /// of unit converts exactly; weight and volume convert only with the
    /// ingredient's `density`, and never with an assumed one, since a guess
    /// would silently change how much the user owns. Anything else, a count
    /// against a weight or volume included, blocks the row.
    ///
    /// A row with no quantity, or a zero one, adds no purchase. Placed on an
    /// ingredient that already exists it therefore does nothing at all, so it
    /// is blocked and counted as skipped; on a new ingredient it still creates it.
    static func place(
        _ row: InventoryImportRow,
        unit: String,
        density: Double?,
        isExisting: Bool
    ) -> InventoryImportPlacement {
        guard let quantity = row.quantity, quantity.isFinite, quantity > 0 else {
            let hasNoQuantity = row.quantity == nil || row.quantity == 0
            return InventoryImportPlacement(quantity: nil, issues: isExisting && hasNoQuantity ? [.nothingToAdd] : [])
        }
        guard let rowUnit = row.unit, rowUnit.rawValue != unit else {
            return InventoryImportPlacement(quantity: quantity, issues: [])
        }
        if let converted = IngredientUnitConverter.convertSameKind(quantity, from: rowUnit.rawValue, to: unit) {
            return InventoryImportPlacement(quantity: converted, issues: [])
        }
        if let density, density > 0,
           let converted = IngredientUnitConverter.convert(quantity, from: rowUnit.rawValue, to: unit, density: density) {
            return InventoryImportPlacement(quantity: converted.value, issues: [.convertedViaDensity])
        }
        return InventoryImportPlacement(
            quantity: nil,
            issues: [.unitMismatch(rowUnit: rowUnit.rawValue, ingredientUnit: unit)]
        )
    }

    // MARK: - Grouping

    private enum Target {
        case existing(Ingredient)
        case library(IngredientLibraryEntry)
        case new(nameKey: String)

        /// Rows sharing a key become one entry. A library entry groups its
        /// aliases together, so "Almond Oil" and "Sweet Almond Oil" don't make
        /// two ingredients carrying one slug.
        var groupKey: GroupKey {
            switch self {
            case .existing(let ingredient): .existing(ObjectIdentifier(ingredient))
            case .library(let entry): .slug(entry.slug)
            case .new(let nameKey): .name(nameKey)
            }
        }
    }

    private enum GroupKey: Hashable {
        case existing(ObjectIdentifier)
        case slug(String)
        case name(String)
    }

    private struct Group {
        let target: Target
        var rows: [(row: InventoryImportRow, rowIssues: [InventoryImportIssue])]
    }

    private static func target(for name: String, in index: IngredientIndex) -> Target {
        if let exact = index.ingredient(named: name) { return .existing(exact) }
        guard let entry = IngredientLibrary.entry(matching: name) else { return .new(nameKey: name.lookupKey) }
        if let installed = index.ingredient(slug: entry.slug) { return .existing(installed) }
        return .library(entry)
    }

    private static func entry(for group: Group) -> InventoryImportEntry {
        switch group.target {
        case .existing(let ingredient):
            let match = InventoryImportMatch(ingredient)
            return InventoryImportEntry(
                resolution: .existing(match),
                lines: lines(of: group, unit: match.unit, density: match.density, isExisting: true)
            )
        case .library(let libraryEntry):
            return newEntry(for: group, libraryEntry: libraryEntry)
        case .new:
            return newEntry(for: group, libraryEntry: nil)
        }
    }

    /// The unit is the first one a usable row gives, else the library entry's,
    /// else grams; the rest of the rows convert into it.
    private static func newEntry(for group: Group, libraryEntry: IngredientLibraryEntry?) -> InventoryImportEntry {
        let usable = group.rows.filter { !$0.rowIssues.contains(where: \.isBlocking) }
        let libraryUnit = libraryEntry.flatMap { IngredientUnit(rawValue: $0.unit) }
        let unit = usable.lazy.compactMap(\.row.unit).first ?? libraryUnit ?? .grams
        let categoryName = group.rows.lazy.compactMap { nonBlank($0.row.categoryName) }.first
            ?? nonBlank(libraryEntry?.category)
        let name = group.rows[0].row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = InventoryImportNewIngredient(name: name, unit: unit, libraryEntry: libraryEntry, categoryName: categoryName)
        return InventoryImportEntry(
            resolution: .newIngredient(new),
            lines: lines(of: group, unit: unit.rawValue, density: libraryEntry?.density, isExisting: false)
        )
    }

    private static func lines(of group: Group, unit: String, density: Double?, isExisting: Bool) -> [InventoryImportLine] {
        group.rows.map { row, rowIssues in
            InventoryImportLine(
                row: row,
                rowIssues: rowIssues,
                placement: place(row, unit: unit, density: density, isExisting: isExisting)
            )
        }
    }

    // MARK: - Validation

    /// The row's own issues plus the ones every source shares, without
    /// repeating one the source already reported.
    private static func validationIssues(of row: InventoryImportRow) -> [InventoryImportIssue] {
        var issues = row.issues
        var found: [InventoryImportIssue] = []
        if row.name.lookupKey.isEmpty { found.append(.missingName) }
        if let quantity = row.quantity, !quantity.isFinite || quantity < 0 { found.append(.invalidQuantity) }
        for issue in found where !issues.contains(issue) {
            issues.append(issue)
        }
        return issues
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
