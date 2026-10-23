import Foundation

/// How much an issue matters to the row that carries it.
enum InventoryImportSeverity: Equatable {
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
enum InventoryImportIssue: Equatable {
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

    var severity: InventoryImportSeverity {
        switch self {
        case .missingName, .invalidQuantity, .unitMismatch, .nothingToAdd: .blocking
        case .convertedViaDensity: .warning
        }
    }

    var isBlocking: Bool { severity == .blocking }

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
        }
    }
}
