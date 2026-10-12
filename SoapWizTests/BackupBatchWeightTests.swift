import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A batch's total weight and unit surviving the backup file (SW-259), and
/// older files without the keys restoring as batches with no recorded weight.
@Suite("Backup – batch weight", .serialized)
@MainActor
struct BackupBatchWeightTests: BackupTestHelpers {

    private func seedWeighed(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        let weighed = Batch(
            recipe: nil,
            recipeName: "Weighed",
            batchCount: 2,
            totalWeight: 2345.5,
            totalWeightUnit: "oz"
        )
        ctx.insert(weighed)
        try ctx.save()
    }

    @Test func roundTrip_PreservesWeightAndUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedWeighed(ctx)

        try roundTripInPlace(ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let weighed = try #require(batches.first { $0.recipeName == "Weighed" })
        #expect(abs(weighed.totalWeight - 2345.5) < 1e-9)
        #expect(weighed.totalWeightUnit == "oz")
    }

    @Test func restore_BackupWithoutKeys_RestoresZeroAndEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedWeighed(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        for index in backup.batches.indices {
            backup.batches[index].totalWeight = nil
            backup.batches[index].totalWeightUnit = nil
        }
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("totalWeight") == false)

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty == false)
        #expect(batches.allSatisfy { $0.totalWeight == 0 && $0.totalWeightUnit.isEmpty })
    }
}
