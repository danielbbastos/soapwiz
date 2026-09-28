import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Finding the row that replaced an open ingredient once it has left the store
/// (SW-89). Unlike `resolve`, this never hands back the gone row itself, which
/// a delete synced from another device may leave attached to its context.
@Suite("LiveIngredient – survivor")
@MainActor
struct LiveIngredientSurvivorTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    @discardableResult
    private func row(_ index: Int, slug: String = "olive-butter", in ctx: ModelContext) throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        ingredient.librarySlug = slug
        ingredient.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
        ctx.insert(ingredient)
        return ingredient
    }

    @Test func survivor_GoneRowStillAttached_ReturnsTheOtherRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gone = try row(1, in: ctx)
        let kept = try row(2, in: ctx)
        try ctx.save()

        let result = LiveIngredient.survivor(slug: "olive-butter", excluding: gone, in: ctx)

        #expect(result === kept)
    }

    @Test func survivor_GoneRowDeleted_ReturnsTheOtherRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let kept = try row(1, in: ctx)
        let gone = try row(2, in: ctx)
        try ctx.save()
        ctx.delete(gone)
        try ctx.save()

        let result = LiveIngredient.survivor(slug: "olive-butter", excluding: gone, in: ctx)

        #expect(result === kept)
    }

    @Test func survivor_SeveralCopies_ReturnsTheLowestUUID() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gone = try row(1, in: ctx)
        try row(3, in: ctx)
        let lowest = try row(2, in: ctx)
        try ctx.save()

        let result = LiveIngredient.survivor(slug: "olive-butter", excluding: gone, in: ctx)

        #expect(result === lowest)
    }

    @Test func survivor_OnlyTheGoneRow_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gone = try row(1, in: ctx)
        try row(2, slug: "shea-butter", in: ctx)
        try ctx.save()

        #expect(LiveIngredient.survivor(slug: "olive-butter", excluding: gone, in: ctx) == nil)
    }

    @Test func survivor_OtherCopyPendingDelete_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gone = try row(1, in: ctx)
        let other = try row(2, in: ctx)
        try ctx.save()
        ctx.delete(other)

        #expect(LiveIngredient.survivor(slug: "olive-butter", excluding: gone, in: ctx) == nil)
    }

    @Test func survivor_EmptySlug_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gone = try row(1, slug: "", in: ctx)
        try row(2, slug: "", in: ctx)
        try ctx.save()

        #expect(LiveIngredient.survivor(slug: "", excluding: gone, in: ctx) == nil)
    }
}
