import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Backup coverage for an ingredient's identity and library state, including a
/// file written before the ingredient library existed.
@Suite("Backup – ingredient library", .serialized)
@MainActor
struct BackupIngredientLibraryTests: BackupTestHelpers {

    @Test func roundTrip_PreservesIdentityAndLibraryState() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let oil = try seededIngredient(ctx)
        let identity = UUID()
        oil.uuid = identity
        oil.librarySlug = "olive-oil"
        oil.hasCustomChemistry = true
        oil.isHidden = true
        try ctx.save()

        try roundTripInPlace(ctx)

        let restored = try seededIngredient(ctx)
        #expect(restored.uuid == identity)
        #expect(restored.librarySlug == "olive-oil")
        #expect(restored.hasCustomChemistry)
        #expect(restored.isHidden)
    }

    @Test func roundTrip_UserCreatedIngredient_StaysUserCreated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        try roundTripInPlace(ctx)

        let restored = try seededIngredient(ctx)
        #expect(restored.librarySlug.isEmpty)
        #expect(!restored.hasCustomChemistry)
        #expect(!restored.isHidden)
    }

    /// A file written before the library has no such keys at all, and must still
    /// decode rather than being rejected as malformed.
    @Test func restore_BackupWrittenBeforeTheLibrary_RestoresAsUserCreated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let oil = try seededIngredient(ctx)
        oil.librarySlug = "olive-oil"
        oil.isHidden = true
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let decoded = try BackupService.decode(try stripLibraryKeys(from: data))
        #expect(decoded.ingredients.first?.librarySlug == nil)
        #expect(decoded.ingredients.first?.uuid == nil)

        try BackupService.restore(decoded, into: ctx)

        let restored = try seededIngredient(ctx)
        #expect(restored.librarySlug.isEmpty)
        #expect(!restored.hasCustomChemistry)
        #expect(!restored.isHidden)
    }

    @Test func restore_BackupWrittenBeforeTheLibrary_GivesEachIngredientItsOwnIdentity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        ctx.insert(Ingredient(name: "Coconut Oil", unit: "g"))
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        try BackupService.restore(try BackupService.decode(try stripLibraryKeys(from: data)), into: ctx)

        let uuids = try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.uuid)
        #expect(uuids.count == 2)
        #expect(Set(uuids).count == 2)
    }

    // MARK: - Helpers

    private func seededIngredient(_ ctx: ModelContext) throws -> Ingredient {
        try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first { $0.name == "Olive Oil" })
    }

    /// Rewrites an exported file as the document it would have been before the
    /// ingredient library: the keys removed rather than nulled.
    private func stripLibraryKeys(from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var json = try #require(object as? [String: Any])
        json["ingredients"] = try #require(json["ingredients"] as? [[String: Any]]).map { ingredient in
            var ingredient = ingredient
            for key in ["uuid", "librarySlug", "hasCustomChemistry", "isHidden"] {
                ingredient.removeValue(forKey: key)
            }
            return ingredient
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
}
