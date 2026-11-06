import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The shopping suggestion dismissal date surviving the backup file. Without it
/// a restore would bring every dismissed suggestion back.
@Suite("Backup – shopping suggestion dismissal", .serialized)
@MainActor
struct BackupShoppingSuggestionDismissalTests: BackupTestHelpers {

    private let dismissed = Date(timeIntervalSince1970: 1_700_000_000)

    private func seed(_ ctx: ModelContext, dismissedAt: Date?) throws {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.shoppingSuggestionDismissedAt = dismissedAt
        ctx.insert(ingredient)
        try ctx.save()
    }

    private func restoredIngredient(in ctx: ModelContext) throws -> Ingredient {
        try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
    }

    @Test func roundTrip_KeepsTheDismissalDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, dismissedAt: dismissed)

        try roundTripInPlace(ctx)

        #expect(try restoredIngredient(in: ctx).shoppingSuggestionDismissedAt == dismissed)
    }

    @Test func roundTrip_NoDismissal_StaysNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, dismissedAt: nil)

        try roundTripInPlace(ctx)

        #expect(try restoredIngredient(in: ctx).shoppingSuggestionDismissedAt == nil)
    }

    /// A file written before the field existed carries no key; stripping it from
    /// a current file is the closest honest stand-in.
    @Test func restore_FileWithoutTheKey_RestoresAsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, dismissedAt: dismissed)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(String(data: data, encoding: .utf8))
        let legacy = try #require(
            json.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("\"suggestionDismissedAt\"") }
                .joined(separator: "\n")
                .data(using: .utf8)
        )
        #expect(legacy.count < data.count)

        try BackupService.restore(try BackupService.decode(legacy), into: ctx)

        #expect(try restoredIngredient(in: ctx).shoppingSuggestionDismissedAt == nil)
    }
}
