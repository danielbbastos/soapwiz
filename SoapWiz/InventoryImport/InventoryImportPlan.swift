import Foundation

/// An ingredient already in the inventory that rows were matched to.
///
/// Everything the review screen and the applier need is copied out when the
/// match is made. A match can be merged away by `DuplicateMerger` while the
/// review screen is open, and reading a stored attribute off the detached row
/// traps — so the slug is kept to find the survivor again (`LiveIngredient`),
/// and nothing else is read off `ingredient` until then.
struct InventoryImportMatch: Equatable {
    let ingredient: Ingredient
    let name: String
    let slug: String
    /// The ingredient's own unit, in the raw value of `IngredientUnit`.
    let unit: String
    let density: Double?
    /// A hidden ingredient still matches, and stays hidden: importing stock
    /// must not change what the user chose to keep out of the list.
    let isHidden: Bool

    init(_ ingredient: Ingredient) {
        self.ingredient = ingredient
        name = ingredient.name
        slug = ingredient.librarySlug
        unit = ingredient.unit
        density = ingredient.density
        isHidden = ingredient.isHidden
    }
}

/// An ingredient the import will create, because nothing in the inventory
/// matched.
///
/// When the name belongs to a library entry whose row isn't installed, the new
/// ingredient adopts the entry — its slug and chemistry, like
/// `IngredientLibraryInstaller` — while keeping the name the user's file used.
struct InventoryImportNewIngredient {
    var name: String
    var unit: IngredientUnit
    var libraryEntry: IngredientLibraryEntry?
    /// `nil` means Others, chosen when the ingredient is created so that a
    /// category the import doesn't need is never made.
    var categoryName: String?
}

enum InventoryImportResolution {
    case existing(InventoryImportMatch)
    case newIngredient(InventoryImportNewIngredient)
}

/// A row once it has been placed on an ingredient: its quantity in that
/// ingredient's unit, and everything worth telling the user about it.
struct InventoryImportLine: Identifiable {
    let row: InventoryImportRow
    /// In the ingredient's unit. `nil` when the row gives no quantity, or can't
    /// be converted.
    private(set) var quantity: Double?
    /// What the source and the quantity check found, which don't change when the
    /// row is matched to another ingredient.
    let rowIssues: [InventoryImportIssue]
    /// What placing the row on its ingredient found, which does.
    private(set) var placementIssues: [InventoryImportIssue]
    /// Always `false` for a blocked row.
    private(set) var isIncluded: Bool

    var id: UUID { row.id }

    var issues: [InventoryImportIssue] { rowIssues + placementIssues }

    var isImportable: Bool { !issues.contains(where: \.isBlocking) }

    init(row: InventoryImportRow, rowIssues: [InventoryImportIssue], placement: InventoryImportPlacement) {
        self.row = row
        self.rowIssues = rowIssues
        quantity = placement.quantity
        placementIssues = placement.issues
        isIncluded = !(rowIssues + placement.issues).contains(where: \.isBlocking)
    }

    /// Ignored for a blocked row.
    mutating func setIncluded(_ included: Bool) {
        isIncluded = included && isImportable
    }

    /// Places the row again, for a different ingredient. A row the user turned
    /// off stays off unless it was blocked before and no longer is.
    fileprivate mutating func place(_ placement: InventoryImportPlacement) {
        let wasBlocked = !isImportable
        quantity = placement.quantity
        placementIssues = placement.issues
        isIncluded = isImportable && (isIncluded || wasBlocked)
    }
}

/// Every row that landed on one ingredient, existing or new.
struct InventoryImportEntry: Identifiable {
    let id: UUID
    fileprivate(set) var resolution: InventoryImportResolution
    fileprivate(set) var lines: [InventoryImportLine]

    init(id: UUID = UUID(), resolution: InventoryImportResolution, lines: [InventoryImportLine]) {
        self.id = id
        self.resolution = resolution
        self.lines = lines
    }

    var name: String {
        switch resolution {
        case .existing(let match): match.name
        case .newIngredient(let new): new.name
        }
    }

    /// The unit the lines' quantities are in.
    var unit: String {
        switch resolution {
        case .existing(let match): match.unit
        case .newIngredient(let new): new.unit.rawValue
        }
    }

    var isNew: Bool {
        if case .newIngredient = resolution { return true }
        return false
    }

    /// For the review screen's "Hidden" stamp.
    var isHidden: Bool {
        if case .existing(let match) = resolution { return match.isHidden }
        return false
    }
}

/// What an import is about to do, for the review screen to edit and the applier
/// to carry out.
struct InventoryImportPlan {
    /// One per ingredient, in the order its first row appeared.
    private(set) var entries: [InventoryImportEntry]
    /// Rows with no ingredient to land on, because they have no name.
    private(set) var unnamed: [InventoryImportLine]

    init(entries: [InventoryImportEntry], unnamed: [InventoryImportLine]) {
        self.entries = entries
        self.unnamed = unnamed
    }

    var rowCount: Int {
        entries.reduce(unnamed.count) { $0 + $1.lines.count }
    }

    /// Rows that will be imported: included, and not blocked. Counted in rows
    /// rather than ingredients, so "imported N, skipped M" is exact.
    var importableCount: Int {
        entries.reduce(0) { total, entry in
            total + entry.lines.filter(\.isIncluded).count
        }
    }

    var skippedCount: Int { rowCount - importableCount }

    mutating func setIncluded(_ included: Bool, forLine id: UUID) {
        for entryIndex in entries.indices {
            guard let lineIndex = entries[entryIndex].lines.firstIndex(where: { $0.id == id }) else { continue }
            entries[entryIndex].lines[lineIndex].setIncluded(included)
            return
        }
    }

    /// Turns every row of the entry on or off, leaving blocked rows off.
    mutating func setIncluded(_ included: Bool, forEntry id: UUID) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == id }) else { return }
        for lineIndex in entries[entryIndex].lines.indices {
            entries[entryIndex].lines[lineIndex].setIncluded(included)
        }
    }

    /// Files a new ingredient under another category. Does nothing for an entry
    /// that matched an ingredient already in the inventory: a match never
    /// changes the ingredient it matched.
    mutating func setCategory(_ name: String?, forEntry id: UUID) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == id }),
              case .newIngredient(var new) = entries[entryIndex].resolution else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        new.categoryName = trimmed?.isEmpty == false ? trimmed : nil
        entries[entryIndex].resolution = .newIngredient(new)
    }

    /// Points the entry at an ingredient the user chose, hidden ones included,
    /// and places its rows on it again: the new ingredient's unit may convert
    /// them differently, or not at all.
    mutating func rematch(entry id: UUID, to ingredient: Ingredient) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == id }) else { return }
        let match = InventoryImportMatch(ingredient)
        entries[entryIndex].resolution = .existing(match)
        for lineIndex in entries[entryIndex].lines.indices {
            let placement = InventoryImportMatcher.place(
                entries[entryIndex].lines[lineIndex].row,
                unit: match.unit,
                density: match.density,
                isExisting: true
            )
            entries[entryIndex].lines[lineIndex].place(placement)
        }
    }
}
