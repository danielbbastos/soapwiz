import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The picker's ticks are kept by id. The duplicate merge can delete a ticked
/// row while the picker is up, and an id alone then matches nothing: the kept
/// copy shows unticked while Done stays enabled and adds nothing.
@Suite("Ingredient picker — ticks across a merge", .serialized)
@MainActor
struct PendingIngredientSelectionTests {

    /// The full schema: `DuplicateMerger` fetches every lookup entity.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    /// A library row. Of two sharing a slug, the lowest `uuid` is the one the
    /// merge keeps.
    private func installed(_ slug: String, _ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: slug, unit: IngredientUnit.grams.rawValue)
        row.librarySlug = slug
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    @Test func toggle_TwiceOnOneRow_LeavesItUnticked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        var selection = PendingIngredientSelection()

        selection.toggle(oil)
        #expect(selection.contains(oil.persistentModelID))
        selection.toggle(oil)

        #expect(!selection.contains(oil.persistentModelID))
        #expect(selection.isEmpty)
    }

    @Test func followMerge_TickedRowMergedAway_TickMovesOntoTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        try ctx.save()
        let capturedID = captured.persistentModelID
        var selection = PendingIngredientSelection()
        selection.toggle(captured)

        try DuplicateMerger.mergeAll(in: ctx)
        selection.followMerge(in: ctx)

        #expect(selection.contains(keep.persistentModelID))
        #expect(!selection.contains(capturedID))
    }

    /// Both copies ticked: one tick on the survivor, not two.
    @Test func followMerge_BothCopiesTicked_SurvivorTickedOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        try ctx.save()
        var selection = PendingIngredientSelection()
        selection.toggle(keep)
        selection.toggle(captured)

        try DuplicateMerger.mergeAll(in: ctx)
        selection.followMerge(in: ctx)
        selection.toggle(keep)

        #expect(selection.isEmpty)
    }

    /// Nothing left to move onto: the tick goes, so Done disables rather than
    /// adding nothing.
    @Test func followMerge_UserRowDeletedOutright_TickIsDropped() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let userOil = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        ctx.insert(userOil)
        try ctx.save()
        var selection = PendingIngredientSelection()
        selection.toggle(userOil)

        ctx.delete(userOil)
        try ctx.save()
        selection.followMerge(in: ctx)

        #expect(selection.isEmpty)
    }

    /// The ordinary path, so the tests above cannot pass by clearing every tick.
    @Test func followMerge_NothingMerged_KeepsEveryTick() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = try installed("olive-oil", 1, in: ctx)
        let userOil = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        ctx.insert(userOil)
        try ctx.save()
        var selection = PendingIngredientSelection()
        selection.toggle(olive)
        selection.toggle(userOil)

        selection.followMerge(in: ctx)

        #expect(selection.contains(olive.persistentModelID))
        #expect(selection.contains(userOil.persistentModelID))
    }
}
