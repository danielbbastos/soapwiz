import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Backup coverage for recipe collections, including the version-1 file that
/// predates them entirely.
@Suite("Backup – recipe collections", .serialized)
@MainActor
struct BackupCollectionTests: BackupTestHelpers {

    /// Membership is many-to-many, so a round-trip has to rebuild both sides of
    /// the link — and rebuild them by index, since two collections may share a name.
    @Test func roundTrip_PreservesCollectionMembership() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let christmas = RecipeCollection(name: "Christmas", colorName: "red")
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(christmas)
        ctx.insert(gifts)
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).collections = [christmas, gifts]
        try ctx.save()

        try roundTripInPlace(ctx)

        let collections = try ctx.fetch(FetchDescriptor<RecipeCollection>())
        #expect(collections.count == 2)
        #expect(Set(collections.map(\.name)) == ["Christmas", "Gifts"])
        #expect(collections.first { $0.name == "Christmas" }?.colorName == "red")

        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(Set(recipe.collections.map(\.name)) == ["Christmas", "Gifts"])
    }

    @Test func roundTrip_UnfiledRecipe_StaysUnfiled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        ctx.insert(RecipeCollection(name: "Gifts"))
        try ctx.save()

        try roundTripInPlace(ctx)

        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.collections.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    /// A version-1 file predates collections entirely: neither the top-level
    /// array nor the per-recipe indices are in the JSON, and it must still decode
    /// rather than being rejected as malformed.
    @Test func restore_VersionOneBackup_RestoresWithNoCollections() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        ctx.insert(RecipeCollection(name: "Christmas"))
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).collections =
            try ctx.fetch(FetchDescriptor<RecipeCollection>())
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let legacy = try stripCollectionKeys(from: data)

        let decoded = try BackupService.decode(legacy)
        #expect(decoded.version == 1)
        #expect(decoded.collections == nil)
        #expect(decoded.recipes.first?.collectionIndices == nil)

        try BackupService.restore(decoded, into: ctx)

        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).isEmpty)
        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.name == "Castile")
        #expect(recipe.collections.isEmpty)
    }

    @Test func restore_CollectionIndexOutOfRange_IsDroppedRatherThanCrashing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.collections = [BackupData.RecipeCollectionDTO(name: "Gifts", colorName: "")]
        backup.recipes[0].collectionIndices = [0, 7]

        try BackupService.restore(backup, into: ctx)

        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.collections.map(\.name) == ["Gifts"])
    }

    // MARK: - Helpers
    /// Rewrites an exported file as the version-1 document it would have been:
    /// the collection keys removed rather than nulled, since a file written
    /// before the feature existed has no such keys at all.
    private func stripCollectionKeys(from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var json = try #require(object as? [String: Any])
        json["version"] = 1
        json.removeValue(forKey: "collections")
        json["recipes"] = try #require(json["recipes"] as? [[String: Any]]).map { recipe in
            var recipe = recipe
            recipe.removeValue(forKey: "collectionIndices")
            return recipe
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
}
