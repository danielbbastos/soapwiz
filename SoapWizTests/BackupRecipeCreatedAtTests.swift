import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A recipe's creation date surviving the backup file. Unlike a shared recipe,
/// a restore is not a new arrival, so the stored date is kept rather than
/// re-stamped — otherwise every recipe would look brand new after a restore.
@Suite("Backup – recipe createdAt", .serialized)
@MainActor
struct BackupRecipeCreatedAtTests: BackupTestHelpers {

    private func seed(_ ctx: ModelContext, createdAt: Date?) throws {
        let recipe = Recipe(name: "Castile", desc: "")
        recipe.createdAt = createdAt
        ctx.insert(recipe)
        try ctx.save()
    }

    /// The restored recipe, re-fetched: `restore` wipes the store first, so any
    /// reference held from before it is dead.
    private func restoredRecipe(in ctx: ModelContext) throws -> Recipe {
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
    }

    @Test func roundTrip_KeepsTheStoredDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        try seed(ctx, createdAt: created)

        try roundTripInPlace(ctx)

        #expect(try restoredRecipe(in: ctx).createdAt == created)
    }

    @Test func encode_CarriesTheCreatedAtKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, createdAt: Date(timeIntervalSince1970: 1_600_000_000))

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"createdAt\""))
    }

    /// A file written before the field existed carries no `createdAt` key. Such a
    /// recipe restores with `nil` so it is never treated as recently added —
    /// stripping the key from a current file is the closest honest stand-in.
    @Test func restore_FileWithoutTheCreatedAtKey_RestoresAsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, createdAt: Date(timeIntervalSince1970: 1_600_000_000))

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))
        let legacy = try #require(
            json.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("\"createdAt\"") }
                .joined(separator: "\n")
                .data(using: .utf8)
        )
        #expect(legacy.count < data.count)

        try BackupService.restore(try BackupService.decode(legacy), into: ctx)

        #expect(try restoredRecipe(in: ctx).createdAt == nil)
    }
}
