import Foundation

/// How a solid bar was made. Not part of the recipe: soap calculators run the
/// same lye maths for both, and the choice is the maker's on the day. It
/// matters afterwards because a cooked bar has less water left to lose, so it
/// cures sooner.
enum SoapProcess: String, CaseIterable, Identifiable {
    case cold
    case hot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cold: "Cold process"
        case .hot: "Hot process"
        }
    }

    /// The process a batch stored, or `nil` for a batch that doesn't cure and
    /// so recorded none.
    static func resolve(_ raw: String) -> SoapProcess? {
        SoapProcess(rawValue: raw)
    }
}
