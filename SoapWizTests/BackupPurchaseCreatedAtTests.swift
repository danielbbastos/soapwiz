import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A purchase's record-creation date surviving the backup file. A restore is not
/// a new arrival, so the stored value is kept rather than re-stamped; a file
/// without it restores as nil.
@Suite("Backup – purchase createdAt", .serialized)
@MainActor
struct BackupPurchaseCreatedAtTests: BackupTestHelpers {

    private func seed(_ ctx: ModelContext, createdAt: Date?) throws {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase = IngredientPurchase(
            provider: nil, dateOfPurchase: .now, quantity: 100, totalPrice: 5,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.createdAt = createdAt
        ctx.insert(purchase)
        purchase.attach(to: oil)
        try ctx.save()
    }

    private func restoredPurchase(in ctx: ModelContext) throws -> IngredientPurchase {
        try #require(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).first)
    }

    @Test func roundTrip_KeepsTheStoredDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        try seed(ctx, createdAt: created)

        try roundTripInPlace(ctx)

        #expect(try restoredPurchase(in: ctx).createdAt == created)
    }

    @Test func roundTrip_NilCreatedAt_StaysNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seed(ctx, createdAt: nil)

        try roundTripInPlace(ctx)

        #expect(try restoredPurchase(in: ctx).createdAt == nil)
    }

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

        #expect(try restoredPurchase(in: ctx).createdAt == nil)
    }
}
