import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// `Recipe.uuid` — the identity the share format and the backup file both carry,
/// and the one thing about a recipe that must not change when anything else about
/// it does.
@Suite("Recipe identity", .serialized)
@MainActor
struct RecipeIdentityTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    @Test func uuid_TwoNewRecipes_AreDistinct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = Recipe(name: "Castile")
        let second = Recipe(name: "Bastille")
        ctx.insert(first)
        ctx.insert(second)
        try ctx.save()

        #expect(first.uuid != second.uuid)
    }

    /// Two recipes that share a *name* still get their own identity — the case
    /// the name could never distinguish.
    @Test func uuid_TwoRecipesSharingAName_AreStillDistinct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let mine = Recipe(name: "Bar")
        let theirs = Recipe(name: "Bar")
        ctx.insert(mine)
        ctx.insert(theirs)
        try ctx.save()

        #expect(mine.uuid != theirs.uuid)
    }

    /// Read back through a context that never saw the original object, so the
    /// value comes off the store rather than out of memory.
    @Test func uuid_SavedThenLoadedInAnotherContext_IsUnchanged() throws {
        let (container, ctx) = try makeContext()
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()
        let expected = recipe.uuid

        let reader = ModelContext(container)
        let loaded = try #require(try reader.fetch(FetchDescriptor<Recipe>()).first)

        #expect(loaded.uuid == expected)
    }

    /// Renaming is what the uuid exists to survive: the name was the only thing
    /// a share could match on before, and it is the thing most likely to change.
    @Test func uuid_AfterRename_IsUnchanged() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()
        let before = recipe.uuid

        recipe.name = "Something Else Entirely"
        try ctx.save()

        #expect(recipe.uuid == before)
    }
}
