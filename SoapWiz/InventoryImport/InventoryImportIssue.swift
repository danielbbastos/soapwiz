import Foundation

/// How much an issue matters to the row that carries it.
nonisolated enum InventoryImportSeverity: Equatable {
    /// The row can't be imported. It is listed under "Can't import" with the reason.
    case blocking
    /// The row still imports; the reason is shown so the user can check it.
    case warning
}

/// A reason a row can't be imported as written, or imports with a caveat.
///
/// Rows come from different sources (a spreadsheet today, an invoice photo
/// later), and each source adds the cases only it can detect — a cell that
/// isn't a number, say — as new cases here. The matcher adds the ones that
/// depend on the inventory.
nonisolated enum InventoryImportIssue: Equatable {
    case missingName
    /// A quantity that is negative or not a finite number. Zero is not an
    /// issue: it reads as "no quantity" and creates no purchase.
    case invalidQuantity
    /// The row's unit and the ingredient's can't be converted into each other.
    /// A count ("un") never converts to a weight or a volume, an ingredient
    /// with an unrecognised unit can't be converted into at all, and weight and
    /// volume only convert when the ingredient records a density: an assumed one
    /// would silently change how much the user owns.
    case unitMismatch(rowUnit: String, ingredientUnit: String)
    /// The quantity crossed between weight and volume using the ingredient's
    /// own density.
    case convertedViaDensity
    /// The row matched an ingredient already in the inventory and gives no
    /// quantity, so importing it would change nothing. It is skipped, and
    /// counted as skipped, rather than reported as imported.
    case nothingToAdd
    /// A unit that isn't one SoapWiz recognises, from the unit column or from
    /// the text after the number in a quantity cell. The associated value is
    /// the text as written.
    case unknownUnit(String)
    /// The quantity cell carries a unit ("500 g") and the unit column names a
    /// different one, so there is no telling which the user meant. Both are
    /// the text as written.
    case conflictingUnits(quantityUnit: String, unitColumn: String)
    /// A price cell that isn't a readable number. The row imports without
    /// that price. The associated value is the cell as written.
    case unreadablePrice(String)
    /// A date cell that isn't a readable date. The row imports without that
    /// date. The associated value is the cell as written.
    case unreadableDate(String)
    /// The user typed the amount in the ingredient's unit because the file's
    /// couldn't be converted: SoapWiz never assumes a density, so the number is
    /// theirs. The file's quantity and unit are kept to show beside it.
    case enteredByHand(fileQuantity: Double, fileUnit: String)

    var severity: InventoryImportSeverity {
        switch self {
        case .missingName, .invalidQuantity, .unitMismatch, .nothingToAdd, .unknownUnit, .conflictingUnits: .blocking
        case .convertedViaDensity, .unreadablePrice, .unreadableDate, .enteredByHand: .warning
        }
    }

    var isBlocking: Bool { severity == .blocking }

    static func fileQuantityText(_ quantity: Double) -> String {
        quantity.formatted(.number.precision(.fractionLength(0...3)))
    }

    /// The explanation shown beside the row.
    var reason: String {
        switch self {
        case .missingName:
            String(localized: "The row has no ingredient name.")
        case .invalidQuantity:
            String(localized: "The quantity isn't a valid amount.")
        case let .unitMismatch(rowUnit, ingredientUnit):
            String(localized: "\(rowUnit) can't be converted to the ingredient's unit, \(ingredientUnit).")
        case .convertedViaDensity:
            String(localized: "Converted between weight and volume using the ingredient's density.")
        case .nothingToAdd:
            String(localized: "Already in your inventory, and no quantity to add.")
        case let .unknownUnit(text):
            String(localized: "\(text) isn't a unit SoapWiz recognises.")
        case let .conflictingUnits(quantityUnit, unitColumn):
            String(localized: "The quantity says \(quantityUnit) but the unit column says \(unitColumn).")
        case let .unreadablePrice(text):
            String(localized: "\(text) isn't a readable price, so the row imports without one.")
        case let .unreadableDate(text):
            String(localized: "\(text) isn't a readable date, so the row imports without one.")
        case let .enteredByHand(fileQuantity, fileUnit):
            String(localized: "Entered by hand. The file says \(Self.fileQuantityText(fileQuantity)) \(fileUnit).")
        }
    }
}
