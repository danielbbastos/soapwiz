import Testing
import Foundation
@testable import SoapWiz

/// The recipe form's open requests (SW-89). On iPhone each is still pushed as
/// the value the list's destinations routed before, so the push is unchanged;
/// on iPad each drives a full-screen cover by its identity.
@Suite("RecipeFormRequest")
@MainActor
struct RecipeFormRequestTests {

    @Test func route_New_IsThePushedFlag() {
        #expect(RecipeFormRequest.new().route == AnyHashable(true))
    }

    @Test func route_Seeded_IsTheSeed() {
        let seed = RecipeSeed(ingredients: [])

        #expect(RecipeFormRequest.seeded(seed).route == AnyHashable(seed))
    }

    @Test func route_Imported_IsThePreparedImport() {
        let prepared = PreparedRecipeImport(draft: RecipeImportDraft(), rows: [])

        #expect(RecipeFormRequest.imported(prepared).route == AnyHashable(prepared))
    }

    @Test func route_Edit_IsTheEditRouteForTheRecipe() {
        let recipe = Recipe(name: "Castile", desc: "")

        #expect(RecipeFormRequest.edit(recipe).route == AnyHashable(RecipeEditRoute(recipe: recipe)))
    }

    /// A second New Recipe, or a second Edit of the same recipe, must be a new
    /// cover rather than the one just closed.
    @Test func id_RepeatedRequests_AreDistinct() {
        let recipe = Recipe(name: "Castile", desc: "")

        #expect(RecipeFormRequest.new().id != RecipeFormRequest.new().id)
        #expect(RecipeFormRequest.edit(recipe).id != RecipeFormRequest.edit(recipe).id)
    }

    @Test func id_SeededAndImported_FollowTheirPayload() {
        let seed = RecipeSeed(ingredients: [])
        let prepared = PreparedRecipeImport(draft: RecipeImportDraft(), rows: [])

        #expect(RecipeFormRequest.seeded(seed).id == seed.id)
        #expect(RecipeFormRequest.imported(prepared).id == prepared.id)
    }
}
