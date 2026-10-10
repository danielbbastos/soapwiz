import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe ingredient order", .serialized)
@MainActor
struct RecipeIngredientOrderTests: RecipeFormTestHelpers {

    private struct Line {
        let name: String
        let amount: Double
        let role: RecipeIngredientRole
    }

    private func makeRecipe(
        in ctx: ModelContext,
        lines: [Line]
    ) -> Recipe {
        let recipe = Recipe(name: "Test")
        recipe.weightUnit = "%"
        recipe.oilWeightUnit = "g"
        recipe.totalOilWeight = 1000
        ctx.insert(recipe)
        for line in lines {
            let ingredient = Ingredient(name: line.name, unit: "g")
            ingredient.sapValue = 0.14
            ctx.insert(ingredient)
            let item = RecipeIngredient(ingredient: ingredient, percentage: line.amount, role: line.role)
            if line.role != .oil {
                item.additiveAmount = line.amount
            }
            ctx.insert(item)
            item.recipe = recipe
        }
        return recipe
    }

    @Test func load_ScrambledOils_OrdersByPercentageDescending() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: [
            Line(name: "Castor Oil", amount: 5, role: .oil),
            Line(name: "Olive Oil", amount: 60, role: .oil),
            Line(name: "Shea Butter", amount: 15, role: .oil),
            Line(name: "Coconut Oil", amount: 20, role: .oil)
        ])
        let model = RecipeFormViewModel()

        model.load(from: recipe)

        #expect(model.oilDrafts.map(\.ingredient.name) == ["Olive Oil", "Coconut Oil", "Shea Butter", "Castor Oil"])
    }

    @Test(arguments: [
        ["Coconut Oil", "Olive Oil", "pine tar"],
        ["pine tar", "Olive Oil", "Coconut Oil"],
        ["Olive Oil", "pine tar", "Coconut Oil"]
    ])
    func load_EqualPercentages_OrdersByNameWhateverTheInsertionOrder(names: [String]) throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: names.map { Line(name: $0, amount: 20, role: .oil) })
        let model = RecipeFormViewModel()

        model.load(from: recipe)

        #expect(model.oilDrafts.map(\.ingredient.name) == ["Coconut Oil", "Olive Oil", "pine tar"])
    }

    @Test func load_AdditivesAndFragrances_OrderByAmountThenName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: [
            Line(name: "Olive Oil", amount: 100, role: .oil),
            Line(name: "Silk", amount: 1, role: .additive),
            Line(name: "Honey", amount: 3, role: .additive),
            Line(name: "Clay", amount: 1, role: .additive),
            Line(name: "Lavender", amount: 2, role: .fragrance),
            Line(name: "Cedar", amount: 5, role: .fragrance),
            Line(name: "Amber", amount: 2, role: .fragrance)
        ])
        let model = RecipeFormViewModel()

        model.load(from: recipe)

        #expect(model.additiveDrafts.map(\.ingredient.name) == ["Honey", "Clay", "Silk"])
        #expect(model.fragranceDrafts.map(\.ingredient.name) == ["Cedar", "Amber", "Lavender"])
    }

    @Test func load_NewOilAdded_AppendsAtEndWithoutResorting() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: [
            Line(name: "Olive Oil", amount: 60, role: .oil),
            Line(name: "Coconut Oil", amount: 40, role: .oil)
        ])
        let model = RecipeFormViewModel()
        model.load(from: recipe)
        let castor = Ingredient(name: "Castor Oil", unit: "g")
        ctx.insert(castor)

        model.addOil(castor)

        #expect(model.oilDrafts.map(\.ingredient.name) == ["Olive Oil", "Coconut Oil", "Castor Oil"])
    }

    @Test func calculatedAmountRows_FollowOilDraftOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: [
            Line(name: "Coconut Oil", amount: 20, role: .oil),
            Line(name: "Olive Oil", amount: 60, role: .oil),
            Line(name: "Castor Oil", amount: 20, role: .oil)
        ])
        let model = RecipeFormViewModel()
        model.load(from: recipe)

        let rows = try #require(model.calculatedAmountRows)
        let oilRows = rows.prefix { !$0.isSummary }.map(\.label)

        #expect(oilRows == ["Olive Oil", "Castor Oil", "Coconut Oil"])
        #expect(oilRows == model.oilDrafts.inRecipeOrder.map(\.ingredient.name))
    }

    @Test func rowSummary_EqualPercentages_NamesOrderedByLookupKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeRecipe(in: ctx, lines: [
            Line(name: "olive Oil", amount: 30, role: .oil),
            Line(name: "Coconut Oil", amount: 30, role: .oil),
            Line(name: "Babassu", amount: 40, role: .oil)
        ])

        let summary = RecipeRowSummary(recipe: recipe)

        #expect(summary.topOils.map(\.name) == ["Babassu", "Coconut Oil", "olive Oil"])
    }
}
