import SwiftUI

/// The height the Ingredients tab's list is given, which caps the expanded
/// cost breakdown bar.
struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension RecipeIngredientsTabView {
    /// The section an ingredient picker was opened from, which decides the
    /// roles it offers and where the picked rows go.
    enum PickerSection: String, Identifiable {
        case oils, additives, fragrances
        /// The merged section a non-soap recipe uses in place of oils + additives.
        case ingredients
        var id: String { rawValue }

        var roles: Set<RecipeIngredientRole> {
            switch self {
            case .oils: return [.oil]
            case .additives: return [.additive]
            case .fragrances: return [.fragrance]
            case .ingredients: return [.oil, .additive]
            }
        }

        /// The merged Ingredients section also offers role-less "Others" ingredients,
        /// so a general recipe isn't limited to oils and additives. Every soap-only
        /// section keeps its exact role set.
        var includesUnroled: Bool { self == .ingredients }

        var pickerConfig: IngredientPickerConfig {
            switch self {
            case .oils: .oils
            case .additives: .additives
            case .fragrances: .fragrances
            case .ingredients: .ingredients
            }
        }
    }
}
