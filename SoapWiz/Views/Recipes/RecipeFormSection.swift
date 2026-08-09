import Foundation

/// The collapsible sections of the recipe form and recipe detail, identifying
/// each one to the "expanding a section scrolls it into view" rule.
enum RecipeFormSection: Hashable {
    case oils, additives, fragrances, calculatedAmounts, extraIngredients, creamSoapAdditions
    case batchTotal
    case product(UUID)
}
