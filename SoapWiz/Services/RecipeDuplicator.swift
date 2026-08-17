import Foundation
import SwiftData

/// Copies a recipe, line items and all, so a variation can be started from an
/// existing formula without retyping it.
///
/// Batches are deliberately not copied: a batch is an immutable record of a
/// production run that actually happened, and it belongs to the recipe it was
/// made from. Neither is `isFavorite` — the pin lifts a row to the top of the
/// list, and a duplicate arriving already pinned would put two near-identical
/// rows up there.
@MainActor
enum RecipeDuplicator {

    @discardableResult
    static func duplicate(_ recipe: Recipe, among existing: [Recipe], into context: ModelContext) -> Recipe {
        let copy = Recipe(name: copyName(of: recipe.name, among: existing), desc: recipe.desc)
        // Copied rather than re-derived: the thumbnail is already the small copy
        // of this exact image, so there is nothing to recompute.
        copy.imageData = recipe.imageData
        copy.thumbnailData = recipe.thumbnailData
        copy.weightUnit = recipe.weightUnit
        copy.totalOilWeight = recipe.totalOilWeight
        copy.oilWeightUnit = recipe.oilWeightUnit
        copy.lyeType = recipe.lyeType
        copy.lyePurity = recipe.lyePurity
        copy.waterParts = recipe.waterParts
        copy.superFat = recipe.superFat
        copy.fragrancePercentage = recipe.fragrancePercentage
        copy.fragranceUnit = recipe.fragranceUnit
        copy.useHybrid = recipe.useHybrid
        copy.kohPercentage = recipe.kohPercentage
        copy.naohPercentage = recipe.naohPercentage
        copy.kohPurity = recipe.kohPurity
        copy.naohPurity = recipe.naohPurity
        copy.isCreamSoap = recipe.isCreamSoap
        copy.useCFM = recipe.useCFM
        copy.cfmNeutralizer = recipe.cfmNeutralizer
        copy.lyeIngredient = recipe.lyeIngredient
        copy.kohLyeIngredient = recipe.kohLyeIngredient
        copy.collections = recipe.collections
        context.insert(copy)

        // Line items whose ingredient hasn't synced yet are copied as they are.
        // Dropping them would quietly make the duplicate a different recipe from
        // the one on screen.
        for line in recipe.ingredients {
            let lineCopy = RecipeIngredient(
                ingredient: line.ingredient,
                percentage: line.percentage,
                role: RecipeIngredientRole(rawValue: line.role) ?? .oil
            )
            lineCopy.additiveAmount = line.additiveAmount
            lineCopy.additiveUnit = line.additiveUnit
            lineCopy.recipe = copy
            context.insert(lineCopy)
        }
        for product in recipe.products {
            let productCopy = RecipeProduct(size: product.size, unitSymbol: product.unitSymbol)
            productCopy.recipe = copy
            context.insert(productCopy)
        }
        return copy
    }

    /// "Castile" → "Castile (copy)", then "Castile (copy 2)", "(copy 3)", … so
    /// duplicating the same recipe repeatedly never collides. Matched on
    /// `lookupKey`, so a differently-cased existing name still counts as taken.
    static func copyName(of name: String, among existing: [Recipe]) -> String {
        let taken = Set(existing.map(\.name).map(\.lookupKey))
        let first = "\(name) (copy)"
        guard taken.contains(first.lookupKey) else { return first }

        var index = 2
        while taken.contains("\(name) (copy \(index))".lookupKey) {
            index += 1
        }
        return "\(name) (copy \(index))"
    }
}
