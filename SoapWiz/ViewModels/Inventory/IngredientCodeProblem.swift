import Foundation

/// Why an ingredient code can't be saved as typed. Each message says what to
/// enter rather than what went wrong.
enum IngredientCodeProblem: Equatable {
    case duplicate
    case tooShort

    var message: String {
        switch self {
        case .duplicate: String(localized: "Enter a code no other ingredient uses.")
        case .tooShort: String(localized: "Enter at least 3 characters.")
        }
    }
}
