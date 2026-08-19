import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe kind – merged ingredients section", .serialized)
@MainActor
struct RecipeKindIngredientRoutingTests: RecipeFormTestHelpers {

    private func makeIngredient(_ ctx: ModelContext, name: String, category: String?) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        if let category {
            let category = IngredientCategory(name: category)
            ctx.insert(category)
            ingredient.category = category
        }
        ctx.insert(ingredient)
        return ingredient
    }

    @Test func addIngredient_OilCategory_LandsInOilDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Soy Wax", category: IngredientCategory.Name.waxes))

        #expect(model.oilDrafts.count == 1)
        #expect(model.additiveDrafts.isEmpty)
        #expect(model.fragranceDrafts.isEmpty)
    }

    @Test func addIngredient_AdditiveCategory_LandsInAdditiveDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Mica", category: IngredientCategory.Name.additives))

        #expect(model.additiveDrafts.count == 1)
        #expect(model.oilDrafts.isEmpty)
    }

    @Test func addIngredient_FragranceCategory_LandsInFragranceDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Lavender EO", category: IngredientCategory.Name.fragrances))

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.oilDrafts.isEmpty)
        #expect(model.additiveDrafts.isEmpty)
    }

    @Test func addIngredient_NoCategory_FallsBackToAdditive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Mystery", category: nil))

        #expect(model.additiveDrafts.count == 1)
    }

    /// The merged section is presentation only: an ingredient added through it
    /// keeps the role its category implies, which is what survives a switch back
    /// to soap and keeps the two sections correct again.
    @Test func addIngredient_MixedPicks_KeepTheirRolesThroughSaveAndLoad() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Lip Balm"
        model.isNonSoapProduct = true
        model.addIngredient(makeIngredient(ctx, name: "Beeswax", category: IngredientCategory.Name.waxes))
        model.addIngredient(makeIngredient(ctx, name: "Vitamin E", category: IngredientCategory.Name.additives))

        let saved = model.save(context: ctx)
        let reloaded = RecipeFormViewModel()
        reloaded.load(from: saved)

        #expect(reloaded.oilDrafts.map(\.ingredient.name) == ["Beeswax"])
        #expect(reloaded.additiveDrafts.map(\.ingredient.name) == ["Vitamin E"])
    }

    @Test func addIngredient_SameIngredientTwice_IsNotDuplicated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        let wax = makeIngredient(ctx, name: "Soy Wax", category: IngredientCategory.Name.waxes)

        model.addIngredient(wax)
        model.addIngredient(wax)

        #expect(model.oilDrafts.count == 1)
    }
}

@Suite("Recipe kind – list row", .serialized)
@MainActor
struct RecipeKindRowSummaryTests: RecipeRowSummaryTestHelpers {

    @Test func soapType_GeneralRecipe_IsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue

        #expect(RecipeRowSummary(recipe: recipe).soapType == nil)
    }

    @Test func kindLabel_GeneralRecipe_IsNeutral() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue

        #expect(RecipeRowSummary(recipe: recipe).kindLabel == "Non-soap product")
    }

    @Test func subtitle_GeneralRecipe_NamesNoSoapType() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue
        recipe.totalOilWeight = 500

        let subtitle = RecipeRowSummary(recipe: recipe).subtitle

        #expect(subtitle.hasPrefix("Non-soap product · "))
        for soapType in [SoapType.solid, .cream, .liquid] {
            #expect(!subtitle.contains(soapType.label))
        }
    }

    @Test func subtitle_SoapRecipe_StillNamesTheSoapType() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.totalOilWeight = 500

        #expect(RecipeRowSummary(recipe: recipe).subtitle.hasPrefix("Solid bar soap · "))
    }
}
