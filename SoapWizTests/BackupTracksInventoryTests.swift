import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The inventory-tracking setting and the per-batch snapshot flag surviving the
/// backup file (SW-81), and older files without either key reading as tracked.
@Suite("Backup – tracksInventory", .serialized)
@MainActor
struct BackupTracksInventoryTests: BackupTestHelpers {

    private func seedUntracked(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        AppSettings.resolve(in: ctx).tracksInventory = false
        let untracked = Batch(recipe: nil, recipeName: "Untracked", batchCount: 1, tracksInventory: false)
        ctx.insert(untracked)
        try ctx.save()
    }

    @Test func roundTrip_PreservesSettingAndBatchFlags() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedUntracked(ctx)

        try roundTripInPlace(ctx)

        #expect(AppSettings.resolve(in: ctx).tracksInventory == false)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let untracked = try #require(batches.first { $0.recipeName == "Untracked" })
        let tracked = try #require(batches.first { $0.recipeName == "Castile" })
        #expect(untracked.tracksInventory == false)
        #expect(tracked.tracksInventory)
    }

    /// A file written before the field existed carries neither key; nil-ing the
    /// DTO fields drops them from the encoded JSON, which is the same file.
    @Test func restore_BackupWithoutKeys_ReadsAsTracked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedUntracked(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.settings.tracksInventory = nil
        for index in backup.batches.indices {
            backup.batches[index].tracksInventory = nil
        }
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("tracksInventory") == false)

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        #expect(AppSettings.resolve(in: ctx).tracksInventory)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty == false)
        #expect(!batches.contains { !$0.tracksInventory })
    }
}
