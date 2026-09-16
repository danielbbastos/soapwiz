import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Hiding a lye takes it out of the choices, but must never take it out of a recipe
/// already built on it: that recipe's batch sheet still has to offer it, or the
/// recipe silently stops producing.
@Suite("Lye candidates — hidden ingredients", .serialized)
@MainActor
struct LyeCandidateVisibilityTests: IngredientFormTestHelpers {

    private func makeLye(_ name: String, hidden: Bool = false, in context: ModelContext) throws -> Ingredient {
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        context.insert(lyes)
        let ingredient = Ingredient(name: name, category: lyes, unit: "g")
        ingredient.isHidden = hidden
        context.insert(ingredient)
        try context.save()
        return ingredient
    }

    @Test func lyeCandidates_NothingHidden_ReturnsVisibleSorted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let naoh = try makeLye("Sodium Hydroxide", in: ctx)
        let koh = try makeLye("Potassium Hydroxide", in: ctx)

        let result = RecipeFormViewModel.lyeCandidates(visible: [naoh, koh], keeping: [nil, nil])

        #expect(result.map(\.name) == ["Potassium Hydroxide", "Sodium Hydroxide"])
    }

    /// The case this exists for.
    @Test func lyeCandidates_RecipesOwnLyeHidden_IsKept() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let koh = try makeLye("Potassium Hydroxide", in: ctx)
        let hiddenNaOH = try makeLye("Sodium Hydroxide", hidden: true, in: ctx)

        let result = RecipeFormViewModel.lyeCandidates(visible: [koh], keeping: [hiddenNaOH, nil])

        #expect(result.map(\.name) == ["Potassium Hydroxide", "Sodium Hydroxide"])
    }

    @Test func lyeCandidates_RecipesLyeAlreadyVisible_IsNotDuplicated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let naoh = try makeLye("Sodium Hydroxide", in: ctx)

        let result = RecipeFormViewModel.lyeCandidates(visible: [naoh], keeping: [naoh, naoh])

        #expect(result.count == 1)
    }

    @Test func lyeCandidates_BothHybridLyesHidden_BothKept() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let hiddenKOH = try makeLye("Potassium Hydroxide", hidden: true, in: ctx)
        let hiddenNaOH = try makeLye("Sodium Hydroxide", hidden: true, in: ctx)

        let result = RecipeFormViewModel.lyeCandidates(visible: [], keeping: [hiddenNaOH, hiddenKOH])

        #expect(result.map(\.name) == ["Potassium Hydroxide", "Sodium Hydroxide"])
    }

    @Test func lyeCandidates_NoVisibleAndNoneSelected_IsEmpty() {
        #expect(RecipeFormViewModel.lyeCandidates(visible: [], keeping: [nil, nil]).isEmpty)
    }

    /// Resolving only ever fills a blank, so a candidate list that has shrunk —
    /// because a lye was hidden — can never unset a lye the recipe already holds.
    @Test func resolveDefaultLyeIngredient_ExistingSelection_IsNotOverwritten() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let naoh = try makeLye("Sodium Hydroxide", in: ctx)
        let koh = try makeLye("Potassium Hydroxide", in: ctx)

        let model = RecipeFormViewModel()
        model.lyeIngredient = naoh
        model.kohLyeIngredient = koh

        model.resolveDefaultLyeIngredient(from: [])

        #expect(model.lyeIngredient?.name == "Sodium Hydroxide")
        #expect(model.kohLyeIngredient?.name == "Potassium Hydroxide")
    }

    @Test func resolveDefaultLyeIngredient_BlankSelection_PicksSodiumHydroxide() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let naoh = try makeLye("Sodium Hydroxide", in: ctx)
        let koh = try makeLye("Potassium Hydroxide", in: ctx)

        let model = RecipeFormViewModel()
        model.resolveDefaultLyeIngredient(from: [koh, naoh])

        #expect(model.lyeIngredient?.name == "Sodium Hydroxide")
    }
}
