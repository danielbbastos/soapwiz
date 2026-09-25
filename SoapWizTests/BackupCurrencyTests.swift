import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The currency setting surviving the backup file (SW-179), and older files
/// without the key restoring as not chosen.
@Suite("Backup – currency", .serialized)
@MainActor
struct BackupCurrencyTests: BackupTestHelpers {

    @Test func roundTrip_PreservesChosenCurrency() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        AppSettings.resolve(in: ctx).currencyCode = "GBP"
        try ctx.save()

        try roundTripInPlace(ctx)

        #expect(AppSettings.resolve(in: ctx).currencyCode == "GBP")
    }

    @Test func restore_BackupWithoutKey_RestoresAsNotChosen() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        AppSettings.resolve(in: ctx).currencyCode = "GBP"
        try ctx.save()
        var backup = try BackupService.makeBackup(from: ctx)
        backup.settings.currencyCode = nil
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("currencyCode") == false)

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        #expect(AppSettings.resolve(in: ctx).currencyCode.isEmpty)
    }
}
