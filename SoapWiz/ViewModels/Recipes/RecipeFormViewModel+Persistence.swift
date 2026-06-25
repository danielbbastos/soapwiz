import Foundation
import SwiftData

/// Loading an existing recipe into the form and persisting the form back to a
/// `Recipe`. Kept apart from the view-model's live editing state for clarity.
extension RecipeFormViewModel {
    func load(from recipe: Recipe) {
        editingRecipe = recipe
        name = recipe.name
        desc = recipe.desc
        weightUnit = recipe.weightUnit
        totalOilWeight = recipe.totalOilWeight
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = recipe.lyePurity
        waterParts = recipe.waterParts
        superFat = recipe.superFat
        fragrancePercentage = recipe.fragrancePercentage
        useHybrid = recipe.useHybrid
        kohPercentage = recipe.kohPercentage
        naohPercentage = recipe.naohPercentage
        kohPurity = recipe.kohPurity
        naohPurity = recipe.naohPurity
        isCreamSoap = recipe.isCreamSoap
        useCFM = recipe.useCFM
        cfmNeutralizer = CFMNeutralizer.resolve(recipe.cfmNeutralizer)
        lyeIngredient = recipe.lyeIngredient
        kohLyeIngredient = recipe.kohLyeIngredient

        oilDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .oil }
            .map { OilIngredientDraft(ingredient: $0.ingredient, amount: $0.percentage, isLocked: true) }
        additiveDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .additive }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }
        fragranceDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .fragrance }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: $0.size, unitSymbol: $0.unitSymbol, modelID: $0.persistentModelID)
        }
        if productDrafts.isEmpty {
            productDrafts = [Self.defaultProductDraft()]
        }
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe = editingRecipe ?? {
            let new = Recipe(name: "", desc: "")
            context.insert(new)
            return new
        }()
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.desc = desc.trimmingCharacters(in: .whitespaces)
        recipe.weightUnit = weightUnit
        recipe.totalOilWeight = totalOilWeight
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = lyePurity
        recipe.waterParts = waterParts
        recipe.superFat = superFat
        recipe.fragrancePercentage = fragrancePercentage
        recipe.useHybrid = useHybrid
        recipe.kohPercentage = kohPercentage
        recipe.naohPercentage = naohPercentage
        recipe.kohPurity = kohPurity
        recipe.naohPurity = naohPurity
        recipe.isCreamSoap = isCreamSoap
        recipe.useCFM = useCFM
        recipe.cfmNeutralizer = cfmNeutralizer.rawValue
        recipe.lyeIngredient = lyeIngredient
        recipe.kohLyeIngredient = kohLyeIngredient

        recipe.ingredients.forEach { context.delete($0) }
        insertIngredients(into: recipe, context: context)

        recipe.products.forEach { context.delete($0) }
        for draft in productDrafts {
            let recipeProduct = RecipeProduct(size: draft.size, unitSymbol: draft.unitSymbol)
            recipeProduct.recipe = recipe
            context.insert(recipeProduct)
        }
        return recipe
    }

    /// Recreates the recipe's ingredient line items from the current drafts.
    private func insertIngredients(into recipe: Recipe, context: ModelContext) {
        for draft in oilDrafts {
            let recipeIngredient = RecipeIngredient(ingredient: draft.ingredient, percentage: draft.amount, role: .oil)
            recipeIngredient.recipe = recipe
            context.insert(recipeIngredient)
        }
        for (drafts, role) in [(additiveDrafts, RecipeIngredientRole.additive), (fragranceDrafts, .fragrance)] {
            for draft in drafts {
                let recipeIngredient = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: role)
                recipeIngredient.additiveAmount = draft.amount
                recipeIngredient.additiveUnit = draft.unit
                recipeIngredient.recipe = recipe
                context.insert(recipeIngredient)
            }
        }
    }
}
