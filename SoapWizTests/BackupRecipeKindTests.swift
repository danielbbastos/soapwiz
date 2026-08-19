import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Backup – recipe kind", .serialized)
@MainActor
struct BackupRecipeKindTests: BackupTestHelpers {

    private func seed(_ ctx: ModelContext, kind: RecipeKind) throws {
        let recipe = Recipe(name: "Beeswax Candle", desc: "")
        recipe.recipeKind = kind.rawValue
        ctx.insert(recipe)
        try ctx.save()
    }

    /// The restored recipe, re-fetched: `restore` wipes the store first, so any
    /// reference held from before it is dead.
    private func restoredRecipe(in ctx: ModelContext) throws -> Recipe {
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
    }

    @Test func roundTrip_NonSoapRecipe_StaysNonSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, kind: .general)

        try roundTripInPlace(ctx)

        #expect(try restoredRecipe(in: ctx).recipeKind == RecipeKind.general.rawValue)
    }

    @Test func roundTrip_SoapRecipe_StaysSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, kind: .soap)

        try roundTripInPlace(ctx)

        #expect(try restoredRecipe(in: ctx).recipeKind == RecipeKind.soap.rawValue)
    }

    @Test func encode_CarriesTheKindKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, kind: .general)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"recipeKind\""))
    }

    /// A file written before the kind existed carries no `recipeKind` key at
    /// all. Stripping it from a current file is the closest honest stand-in —
    /// the encoder writes one key per line, sorted.
    @Test func restore_FileWithoutTheKindKey_RestoresAsSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, kind: .general)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))
        let legacy = try #require(
            json.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("\"recipeKind\"") }
                .joined(separator: "\n")
                .data(using: .utf8)
        )
        #expect(legacy.count < data.count)

        try BackupService.restore(try BackupService.decode(legacy), into: ctx)

        #expect(try restoredRecipe(in: ctx).recipeKind == RecipeKind.soap.rawValue)
    }
}
