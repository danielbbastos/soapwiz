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
    /// Kept apart from `isIncluded`, which is derived, so that a row the user
    /// turned off stays off through being blocked and unblocked again.
    private(set) var isTurnedOff = false
    /// What the user typed, in the ingredient's unit, for a row whose unit the
    /// ingredient couldn't take. Set only while that amount stands: placing the
    /// row on an ingredient again drops it, since the unit it was typed in may
    /// no longer be the ingredient's.
    private(set) var enteredQuantity: Double?

    /// Always `false` for a blocked row.
    var isIncluded: Bool { isImportable && !isTurnedOff }

    var id: UUID { row.id }

    var issues: [InventoryImportIssue] { rowIssues + placementIssues }

    var isImportable: Bool { !issues.contains(where: \.isBlocking) }

    /// Whether the user can type the amount: the row is blocked only by a unit
    /// the ingredient can't take, which they can answer by giving the amount in
    /// the ingredient's own unit. It stays true once an amount is entered, so
    /// that it can be changed or undone.
    var canEnterQuantity: Bool {
        if enteredQuantity != nil { return true }
        guard !rowIssues.contains(where: \.isBlocking) else { return false }
        let blocking = placementIssues.filter(\.isBlocking)
        return !blocking.isEmpty && blocking.allSatisfy { issue in
            if case .unitMismatch = issue { return true }
            return false
        }
    }

    init(row: InventoryImportRow, rowIssues: [InventoryImportIssue], placement: InventoryImportPlacement) {
        self.row = row
        self.rowIssues = rowIssues
        quantity = placement.quantity
        placementIssues = placement.issues
    }

    /// Ignored for a blocked row.
    mutating func setIncluded(_ included: Bool) {
        guard isImportable else { return }
        isTurnedOff = !included
    }

    /// Places the row again, for a different ingredient. Whether the user
    /// turned it off is left alone, so it comes back on only if they never did.
    /// An amount typed by hand is dropped.
    fileprivate mutating func place(_ placement: InventoryImportPlacement) {
        quantity = placement.quantity
        placementIssues = placement.issues
        enteredQuantity = nil
    }

    /// Takes `amount`, in the ingredient's unit, as the row's quantity. Ignored
    /// unless it is a positive number and the row can have one entered; the
    /// file's quantity and unit stay on the row, and are named in the note that
    /// replaces the unit mismatch.
    fileprivate mutating func enterQuantity(_ amount: Double) {
        guard amount.isFinite, amount > 0, canEnterQuantity,
              let fileQuantity = row.quantity, let fileUnit = row.unit else { return }
        quantity = amount
        enteredQuantity = amount
        placementIssues = placementIssues.filter { issue in
            switch issue {
            case .unitMismatch, .enteredByHand: false
            default: true
            }
        } + [.enteredByHand(fileQuantity: fileQuantity, fileUnit: fileUnit.rawValue)]
    }
}

/// Every row that landed on one ingredient, existing or new.
struct InventoryImportEntry: Identifiable {
    let id: UUID
    /// What the matcher decided, kept so a change the user made can be undone.
    let originalResolution: InventoryImportResolution
    fileprivate(set) var resolution: InventoryImportResolution
    fileprivate(set) var lines: [InventoryImportLine]

    init(id: UUID = UUID(), resolution: InventoryImportResolution, lines: [InventoryImportLine]) {
        self.id = id
        originalResolution = resolution
        self.resolution = resolution
        self.lines = lines
    }

    /// Whether the user pointed the entry at a different ingredient than the
    /// matcher chose. Editing a new ingredient's category is not a rematch.
    var isRematched: Bool {
        switch (originalResolution, resolution) {
        case let (.existing(original), .existing(current)): original != current
        case (.newIngredient, .newIngredient): false
        case (.existing, .newIngredient), (.newIngredient, .existing): true
        }
    }

    /// Only an entry the matcher found no ingredient for can go back to being
    /// new: one it matched to the inventory names an ingredient the file
    /// already belongs to, and creating a second would duplicate it.
    var startedAsNew: Bool {
        if case .newIngredient = originalResolution { return true }
        return false
    }

    /// Points the entry at `resolution` and places its rows on that
    /// ingredient's unit again, since the new unit may convert them
    /// differently, or not at all.
    fileprivate mutating func resolve(as resolution: InventoryImportResolution) {
        self.resolution = resolution
        for lineIndex in lines.indices {
            placeLine(at: lineIndex)
        }
    }

    /// Places one row on the entry's current ingredient, as the matcher would.
    fileprivate mutating func placeLine(at index: Int) {
        let density: Double?
        let isExisting: Bool
        switch resolution {
        case .existing(let match):
            density = match.density
            isExisting = true
        case .newIngredient(let new):
            density = new.libraryEntry?.density
            isExisting = false
        }
        let placement = InventoryImportMatcher.place(
            lines[index].row,
            unit: unit,
            density: density,
            isExisting: isExisting
        )
        lines[index].place(placement)
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

    private func lineLocation(of id: UUID) -> (entry: Int, line: Int)? {
        for entryIndex in entries.indices {
            if let lineIndex = entries[entryIndex].lines.firstIndex(where: { $0.id == id }) {
                return (entryIndex, lineIndex)
            }
        }
        return nil
    }

    mutating func setIncluded(_ included: Bool, forLine id: UUID) {
        guard let location = lineLocation(of: id) else { return }
        entries[location.entry].lines[location.line].setIncluded(included)
    }

    /// Imports the row with `amount`, in its ingredient's unit, in place of the
    /// file's quantity, which couldn't be converted. Does nothing for a row that
    /// isn't blocked only by that, or for an amount that isn't positive.
    mutating func enterQuantity(_ amount: Double, forLine id: UUID) {
        guard let location = lineLocation(of: id) else { return }
        entries[location.entry].lines[location.line].enterQuantity(amount)
    }

    /// Undoes `enterQuantity`: the row is placed on its ingredient again, which
    /// brings the unit mismatch back.
    mutating func clearEnteredQuantity(forLine id: UUID) {
        guard let location = lineLocation(of: id),
              entries[location.entry].lines[location.line].enteredQuantity != nil else { return }
        entries[location.entry].placeLine(at: location.line)
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
        entries[entryIndex].resolve(as: .existing(InventoryImportMatch(ingredient)))
    }

    /// Undoes `rematch`, going back to what the matcher chose, the category of
    /// a new ingredient included.
    mutating func resetMatch(entry id: UUID) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[entryIndex].resolve(as: entries[entryIndex].originalResolution)
    }
}
