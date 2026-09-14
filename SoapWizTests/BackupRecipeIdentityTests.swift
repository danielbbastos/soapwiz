import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A recipe's identity surviving the backup file.
///
/// Without this the identity dies at the first device migration: the user
/// restores their library, every recipe is minted fresh, and a recipe they
/// shared before the restore is no longer recognisable when it comes back.
@Suite("Backup – recipe identity", .serialized)
@MainActor
struct BackupRecipeIdentityTests: BackupTestHelpers {

    @discardableResult
    private func seed(_ ctx: ModelContext, names: [String]) throws -> [UUID] {
        let recipes = names.map { name -> Recipe in
            let recipe = Recipe(name: name, desc: "")
            ctx.insert(recipe)
            return recipe
        }
        try ctx.save()
        return recipes.map(\.uuid)
    }

    /// Re-fetched by name: `restore` wipes the store first, so any reference
    /// held from before it is dead, and the relationship order is not stable.
    private func restoredUUID(named name: String, in ctx: ModelContext) throws -> UUID {
        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        return try #require(recipes.first { $0.name == name }).uuid
    }

    @Test func roundTrip_Recipe_KeepsItsIdentity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let before = try #require(try seed(ctx, names: ["Castile"]).first)

        try roundTripInPlace(ctx)

        #expect(try restoredUUID(named: "Castile", in: ctx) == before)
    }

    @Test func roundTrip_SeveralRecipes_EachKeepsItsOwn() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let names = ["Castile", "Bastille", "Kitchen Bar"]
        let before = try seed(ctx, names: names)

        try roundTripInPlace(ctx)

        let after = try names.map { try restoredUUID(named: $0, in: ctx) }
        #expect(after == before)
    }

    @Test func encode_CarriesTheUUIDKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, names: ["Castile"])

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"uuid\""))
    }

    /// A file written before identities existed carries no `uuid` key at all.
    /// Stripping it from a current file is the closest honest stand-in — the
    /// encoder writes one key per line, sorted.
    ///
    /// Every recipe must come back with an identity of its *own*: restoring them
    /// all under one would recreate the exact problem the migration backfill
    /// exists to repair.
    @Test func restore_FileWithoutTheUUIDKey_GivesEachRecipeItsOwnIdentity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, names: ["Castile", "Bastille", "Kitchen Bar"])

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))
        let legacy = try #require(
            json.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("\"uuid\"") }
                .joined(separator: "\n")
                .data(using: .utf8)
        )
        #expect(legacy.count < data.count)

        try BackupService.restore(try BackupService.decode(legacy), into: ctx)

        let restored = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(restored.count == 3)
        #expect(Set(restored.map(\.uuid)).count == 3)
    }
}
