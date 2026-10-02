import Testing
import Foundation
@testable import SoapWiz

/// The recipe form's open requests (SW-89). On iPhone each is pushed as the
/// value the list's destinations route; on iPad each drives a full-screen cover
/// by its identity.
@Suite("RecipeFormRequest")
@MainActor
struct RecipeFormRequestTests {

    /// Each route is checked by its type as well as its value: a destination
    /// matches on the pushed value's type, and a route wrapped in `AnyHashable`
    /// compares equal yet matches nothing, leaving a blank screen (SW-206).
    @Test func route_New_IsThePushedFlag() throws {
        let route = RecipeFormRequest.new().route

        #expect(type(of: route) == Bool.self)
        #expect(try #require(route as? Bool))
    }

    @Test func route_Seeded_IsTheSeed() throws {
        let seed = RecipeSeed(ingredients: [])
        let route = RecipeFormRequest.seeded(seed).route

        #expect(type(of: route) == RecipeSeed.self)
        #expect(try #require(route as? RecipeSeed) == seed)
    }

    @Test func route_Imported_IsThePreparedImport() throws {
        let prepared = PreparedRecipeImport(draft: RecipeImportDraft(), rows: [])
        let route = RecipeFormRequest.imported(prepared).route

        #expect(type(of: route) == PreparedRecipeImport.self)
        #expect(try #require(route as? PreparedRecipeImport) == prepared)
    }

    @Test func route_Edit_IsTheEditRouteForTheRecipe() throws {
        let recipe = Recipe(name: "Castile", desc: "")
        let route = RecipeFormRequest.edit(recipe).route

        #expect(type(of: route) == RecipeEditRoute.self)
        #expect(try #require(route as? RecipeEditRoute) == RecipeEditRoute(recipe: recipe))
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
