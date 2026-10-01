import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A batch's cure length and process, and the cure reminders setting,
/// surviving the backup file (SW-193), and older files without the keys
/// restoring as batches that don't cure.
@Suite("Backup – cure", .serialized)
@MainActor
struct BackupCureTests: BackupTestHelpers {

    private func seedCuring(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        AppSettings.resolve(in: ctx).cureNotificationsEnabled = true
        let curing = Batch(
            recipe: nil,
            recipeName: "Curing",
            batchCount: 1,
            cureDays: 42,
            process: SoapProcess.hot.rawValue,
            cureBand: CureBand.typicalHot.rawValue
        )
        ctx.insert(curing)
        try ctx.save()
    }

    @Test func roundTrip_PreservesCureAndSetting() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCuring(ctx)

        try roundTripInPlace(ctx)

        #expect(AppSettings.resolve(in: ctx).cureNotificationsEnabled)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let curing = try #require(batches.first { $0.recipeName == "Curing" })
        #expect(curing.cureDays == 42)
        #expect(SoapProcess.resolve(curing.process) == .hot)
        #expect(CureBand.resolve(curing.cureBand) == .typicalHot)
    }

    @Test func roundTrip_BatchWithoutCure_StaysWithoutCure() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCuring(ctx)

        try roundTripInPlace(ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let plain = try #require(batches.first { $0.recipeName == "Castile" })
        #expect(plain.cureDays == 0)
        #expect(SoapProcess.resolve(plain.process) == nil)
    }

    /// A file written before the fields existed carries none of the keys;
    /// nil-ing the DTO fields drops them from the encoded JSON.
    @Test func restore_BackupWithoutKeys_RestoresNoCureAndKeepsTheDeviceSetting() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCuring(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.settings.cureNotificationsEnabled = nil
        for index in backup.batches.indices {
            backup.batches[index].cureDays = nil
            backup.batches[index].process = nil
            backup.batches[index].cureBand = nil
        }
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("cureDays") == false)
        #expect(json.contains("cureNotificationsEnabled") == false)

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        #expect(AppSettings.resolve(in: ctx).cureNotificationsEnabled)
        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty == false)
        #expect(json.contains("cureBand") == false)
        #expect(batches.allSatisfy { $0.cureDays == 0 && $0.process.isEmpty && $0.cureBand.isEmpty })
    }
}
