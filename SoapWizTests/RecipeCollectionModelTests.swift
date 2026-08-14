import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Collections are a many-to-many overlay over the flat recipe list: a recipe
/// belongs to several at once, and deleting one is a filing decision that must
/// never reach the recipes themselves.
@Suite("Recipe collections", .serialized)
@MainActor
struct RecipeCollectionTests: RecipeCollectionTestHelpers {

    // MARK: - Membership

    @Test func collections_NewRecipe_StartsUnfiled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
    }

    @Test func collections_RecipeInTwo_IsListedByBoth() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        #expect(recipe.collections.count == 2)
        #expect(christmas.recipes.map(\.name) == ["Cinnamon Bar"])
        #expect(gifts.recipes.map(\.name) == ["Cinnamon Bar"])
    }

    @Test func collections_ManyRecipesOneCollection_AllAppearOnTheInverse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        for name in ["Castile", "Bastille", "Coconut Bar"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            recipe.collections = [gifts]
        }
        try ctx.save()

        #expect(Set(gifts.recipes.map(\.name)) == ["Castile", "Bastille", "Coconut Bar"])
    }

    // MARK: - Deletion

    /// The `.nullify` rule in both directions is the point of the whole model: a
    /// collection is a label, and removing a label must not remove what it named.
    @Test func deleteCollection_NullifiesLinkAndKeepsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        ctx.delete(christmas)
        try ctx.save()

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        #expect(recipes.first?.collections.isEmpty == true)
    }

    @Test func deleteCollection_RecipeInTwo_KeepsTheOtherMembership() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        ctx.delete(christmas)
        try ctx.save()

        #expect(recipe.collections.map(\.name) == ["Gifts"])
    }

    @Test func deleteRecipe_KeepsCollectionAlive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Castile")
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts]
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let collections = try ctx.fetch(FetchDescriptor<RecipeCollection>())
        #expect(collections.count == 1)
        #expect(collections.first?.recipes.isEmpty == true)
    }

    // MARK: - Colour

    @Test func color_EmptyColorName_ResolvesToNeutral() {
        #expect(RecipeCollection(name: "Gifts").color == .neutral)
    }

    @Test func color_UnknownColorName_ResolvesToNeutral() {
        #expect(RecipeCollection(name: "Gifts", colorName: "chartreuse").color == .neutral)
    }

    @Test func color_KnownColorName_ResolvesToThatCase() {
        #expect(RecipeCollection(name: "Gifts", colorName: "teal").color == .teal)
    }

    // MARK: - Sorting

    @Test func sortedByName_MixedCaseAndAccents_OrdersByLookupKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collections = ["gifts", "Áutumn", "Christmas"].map { RecipeCollection(name: $0) }
        collections.forEach { ctx.insert($0) }
        try ctx.save()

        #expect(collections.sortedByName.map(\.name) == ["Áutumn", "Christmas", "gifts"])
    }

    /// Two rows sharing a name is the unmerged-CloudKit-duplicate case. The order
    /// has to be stable anyway, or the recipe form's dirty check fires on its own.
    @Test func sortedByName_SameName_BreaksTieOnUUIDDeterministically() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let low = RecipeCollection(name: "Gifts")
        low.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = RecipeCollection(name: "Gifts")
        high.uuid = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        ctx.insert(low)
        ctx.insert(high)
        try ctx.save()

        #expect([high, low].sortedByName.map(\.uuid) == [low.uuid, high.uuid])
        #expect([low, high].sortedByName.map(\.uuid) == [low.uuid, high.uuid])
    }

    @Test func sortedByName_Empty_ReturnsEmpty() {
        #expect([RecipeCollection]().sortedByName.isEmpty)
    }
}
