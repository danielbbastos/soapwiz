import Foundation
import SwiftData

/// Turns stored recipes into a payload another SoapWiz can read back exactly.
///
/// Reads the `Recipe` models directly rather than going through
/// `RecipeFormViewModel` the way `RecipeTextExporter` does. The text exporter
/// has to agree with what the detail screen displays, so it borrows the screen's
/// own calculations; this one has to agree with what is *stored*, and every
/// calculated figure downstream is reproduced from these fields anyway.
@MainActor
enum RecipeTransferEncoder {

    /// Builds the payload for one or more recipes, pooling the ingredients they
    /// share.
    static func payload(for recipes: [Recipe], exportedAt: Date = .now) -> RecipeTransferData {
        var pool = RecipeTransferIngredientPool()
        let encoded = recipes.map { recipe in
            self.recipe(recipe, pool: &pool)
        }
        return RecipeTransferData(
            exportedAt: exportedAt,
            ingredients: pool.ingredients,
            recipes: encoded
        )
    }

    /// The bytes of a `.soapwizrecipe` file. Plain JSON: nothing reads a file by
    /// eye, so it has no reason to be compressed or armoured the way the
    /// clipboard marker is.
    static func fileData(for recipes: [Recipe], exportedAt: Date = .now) throws -> Data {
        try RecipeTransferCoding.encoder.encode(payload(for: recipes, exportedAt: exportedAt))
    }

    // MARK: - Recipe

    private static func recipe(_ recipe: Recipe, pool: inout RecipeTransferIngredientPool) -> RecipeTransferRecipe {
        RecipeTransferRecipe(
            name: recipe.name,
            desc: recipe.desc,
            recipeKind: recipe.recipeKind,
            weightUnit: recipe.weightUnit,
            totalOilWeight: recipe.totalOilWeight,
            oilWeightUnit: recipe.oilWeightUnit,
            lyeType: recipe.lyeType,
            lyePurity: recipe.lyePurity,
            waterParts: recipe.waterParts,
            superFat: recipe.superFat,
            useHybrid: recipe.useHybrid,
            kohPercentage: recipe.kohPercentage,
            naohPercentage: recipe.naohPercentage,
            kohPurity: recipe.kohPurity,
            naohPurity: recipe.naohPurity,
            isCreamSoap: recipe.isCreamSoap,
            useCFM: recipe.useCFM,
            cfmNeutralizer: recipe.cfmNeutralizer,
            fragrancePercentage: recipe.fragrancePercentage,
            fragranceUnit: recipe.fragranceUnit,
            collectionNames: recipe.collections.sortedByName.map(\.name),
            ingredients: lineItems(of: recipe, pool: &pool),
            products: recipe.products.map {
                RecipeTransferProduct(size: $0.size, unitSymbol: $0.unitSymbol)
            }
        )
    }

    /// Line items whose ingredient is missing are dropped rather than carried.
    ///
    /// With CloudKit mirroring on, a `RecipeIngredient` can arrive before the
    /// `Ingredient` it points at — `RecipeFormViewModel.unresolvedLineItemCount`
    /// exists for exactly that window. Such a row has no name to resolve
    /// against the recipient's inventory and no chemistry to offer them, so
    /// there is nothing to send.
    private static func lineItems(
        of recipe: Recipe,
        pool: inout RecipeTransferIngredientPool
    ) -> [RecipeTransferLineItem] {
        recipe.ingredients.compactMap { line in
            guard let ingredient = line.ingredient else { return nil }
            return RecipeTransferLineItem(
                ingredientIndex: pool.index(of: ingredient),
                role: line.role,
                percentage: line.percentage,
                additiveAmount: line.additiveAmount,
                additiveUnit: line.additiveUnit
            )
        }
    }
}

/// Collects each referenced ingredient once, in the order it was first seen, and
/// hands back the index that identifies it inside the payload.
///
/// Keyed on `persistentModelID` rather than on the name: two rows can share a
/// name while CloudKit is still collapsing a duplicate, and merging them here
/// would quietly send one ingredient's chemistry under both rows' recipes.
@MainActor
private struct RecipeTransferIngredientPool {
    private(set) var ingredients: [RecipeTransferIngredient] = []
    private var indices: [PersistentIdentifier: Int] = [:]

    mutating func index(of ingredient: Ingredient) -> Int {
        if let existing = indices[ingredient.persistentModelID] { return existing }
        let index = ingredients.count
        indices[ingredient.persistentModelID] = index
        ingredients.append(
            RecipeTransferIngredient(
                name: ingredient.name,
                unit: ingredient.unit,
                sapValue: ingredient.sapValue,
                kohSapValue: ingredient.kohSapValue,
                density: ingredient.density,
                fattyAcidProfile: ingredient.fattyAcidProfile
            )
        )
        return index
    }
}
