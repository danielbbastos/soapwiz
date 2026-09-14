import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The repair pass for the migration that added `Recipe.uuid`.
///
/// Core Data backfills a new non-optional column from the single default
/// recorded in the model, so every recipe that existed before the field came out
/// of the migration sharing one identity. Verified against a real store before
/// this was written: four seeded recipes, four rows, one distinct uuid.
@Suite("Recipe identity backfill", .serialized)
@MainActor
struct RecipeIdentityBackfillTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// Recipes as the migration leaves them: distinct rows, one shared uuid.
    @discardableResult
    private func seedMigrated(_ ctx: ModelContext, names: [String]) throws -> [Recipe] {
        let shared = UUID()
        let recipes = names.map { name -> Recipe in
            let recipe = Recipe(name: name)
            recipe.uuid = shared
            ctx.insert(recipe)
            return recipe
        }
        try ctx.save()
        return recipes
    }

    @Test func repair_RecipesSharingAnIdentity_AllEndUpDistinct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipes = try seedMigrated(ctx, names: ["Pure Castile", "Bastille", "Kitchen Bar", "Butter Bar"])

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 4)
        #expect(Set(recipes.map(\.uuid)).count == 4)
    }

    /// The pass must not touch a library created after the field existed.
    @Test func repair_DistinctIdentities_ChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = Recipe(name: "Castile")
        let second = Recipe(name: "Bastille")
        ctx.insert(first)
        ctx.insert(second)
        try ctx.save()
        let before = [first.uuid, second.uuid]

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 0)
        #expect([first.uuid, second.uuid] == before)
    }

    /// It runs on every launch, so a second pass over a repaired store must be
    /// a no-op — otherwise every launch would hand every recipe a new identity
    /// and the format would be carrying noise.
    @Test func repair_RunTwice_SecondPassIsANoOp() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipes = try seedMigrated(ctx, names: ["Castile", "Bastille"])
        try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)
        let afterFirst = recipes.map(\.uuid)

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 0)
        #expect(recipes.map(\.uuid) == afterFirst)
    }

    /// One recipe cannot collide with anything, so the value the migration gave
    /// it is already usable and is left alone.
    @Test func repair_SingleRecipe_LeavesItAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipes = try seedMigrated(ctx, names: ["Castile"])
        let only = try #require(recipes.first)
        let before = only.uuid

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 0)
        #expect(only.uuid == before)
    }

    @Test func repair_EmptyStore_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container

        #expect(try RecipeIdentityBackfill.repairSharedIdentities(in: ctx) == 0)
    }

    /// Only the colliding group is re-minted; a recipe added after the migration
    /// keeps the identity it was born with.
    @Test func repair_MigratedAndNewRecipesMixed_OnlyTheCollidingOnesChange() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let migrated = try seedMigrated(ctx, names: ["Castile", "Bastille"])
        let fresh = Recipe(name: "Added Later")
        ctx.insert(fresh)
        try ctx.save()
        let freshUUID = fresh.uuid

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 2)
        #expect(fresh.uuid == freshUUID)
        #expect(Set(migrated.map(\.uuid) + [fresh.uuid]).count == 3)
    }

    /// The repair has to survive the launch that ran it, or the next launch
    /// finds the same collision and mints again.
    @Test func repair_AfterSave_IsVisibleToAnotherContext() throws {
        let (container, ctx) = try makeContext()
        try seedMigrated(ctx, names: ["Castile", "Bastille"])

        try RecipeIdentityBackfill.repairSharedIdentities(in: ctx)

        let reader = ModelContext(container)
        let loaded = try reader.fetch(FetchDescriptor<Recipe>())
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.uuid)).count == 2)
    }
}
