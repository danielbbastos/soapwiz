import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The repair pass for the migration that added `Ingredient.uuid`, which leaves
/// every pre-existing ingredient sharing the single default value.
@Suite("Ingredient identity backfill", .serialized)
@MainActor
struct IngredientIdentityBackfillTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// Ingredients as the migration leaves them: distinct rows, one shared uuid.
    @discardableResult
    private func seedMigrated(_ ctx: ModelContext, names: [String]) throws -> [Ingredient] {
        let shared = UUID()
        let ingredients = names.map { name -> Ingredient in
            let ingredient = Ingredient(name: name, unit: "g")
            ingredient.uuid = shared
            ctx.insert(ingredient)
            return ingredient
        }
        try ctx.save()
        return ingredients
    }

    @Test func repair_IngredientsSharingAnIdentity_AllEndUpDistinct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = try seedMigrated(ctx, names: ["Olive Oil", "Coconut Oil", "Castor Oil"])

        let repaired = try IngredientIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 3)
        #expect(Set(ingredients.map(\.uuid)).count == 3)
    }

    @Test func repair_DistinctIdentities_AreLeftUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(olive)
        ctx.insert(coconut)
        try ctx.save()
        let before = [olive.uuid, coconut.uuid]

        let repaired = try IngredientIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 0)
        #expect([olive.uuid, coconut.uuid] == before)
    }

    @Test func repair_OnlyTheCollidingGroupIsReMinted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedMigrated(ctx, names: ["Olive Oil", "Coconut Oil"])
        let independent = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(independent)
        try ctx.save()
        let independentUUID = independent.uuid

        let repaired = try IngredientIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 2)
        #expect(independent.uuid == independentUUID)
    }

    @Test func repair_RunTwice_SecondPassChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = try seedMigrated(ctx, names: ["Olive Oil", "Coconut Oil"])
        try IngredientIdentityBackfill.repairSharedIdentities(in: ctx)
        let afterFirst = ingredients.map(\.uuid)

        let repaired = try IngredientIdentityBackfill.repairSharedIdentities(in: ctx)

        #expect(repaired == 0)
        #expect(ingredients.map(\.uuid) == afterFirst)
    }

    @Test func repair_EmptyStore_ReturnsZero() throws {
        let (container, ctx) = try makeContext()
        _ = container

        #expect(try IngredientIdentityBackfill.repairSharedIdentities(in: ctx) == 0)
    }
}
