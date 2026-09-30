import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The batch code surviving the backup file (SW-175), and older files without
/// the key still decoding.
@Suite("Backup – batch code", .serialized)
@MainActor
struct BackupBatchCodeTests: BackupTestHelpers {

    private func seedCodedBatches(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        ctx.insert(Batch.mock(code: "LAV-260930-01", recipeName: "Lavender"))
        ctx.insert(Batch.mock(code: "2026/14", recipeName: "Rose"))
        try ctx.save()
    }

    @Test func roundTrip_PreservesGeneratedAndHandTypedCodes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCodedBatches(ctx)

        try roundTripInPlace(ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let lavender = try #require(batches.first { $0.recipeName == "Lavender" })
        let rose = try #require(batches.first { $0.recipeName == "Rose" })
        #expect(lavender.code == "LAV-260930-01")
        #expect(rose.code == "2026/14")
    }

    @Test func makeBackup_CarriesEachBatchCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCodedBatches(ctx)

        let backup = try BackupService.makeBackup(from: ctx)

        #expect(Set(backup.batches.compactMap(\.code)) == ["LAV-260930-01", "2026/14", ""])
    }

    /// A file written before the field existed has no `code` key on its
    /// batches; nil-ing the DTO field drops it from the JSON, which is that file.
    @Test func restore_BackupWithoutCodeKey_RestoresBatchesWithoutCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCodedBatches(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        for index in backup.batches.indices {
            backup.batches[index].code = nil
        }
        let firstBatch = try #require(backup.batches.first)
        let batchJSON = try #require(String(data: try JSONEncoder().encode(firstBatch), encoding: .utf8))
        #expect(batchJSON.contains("\"code\"") == false)

        try BackupService.restore(try BackupService.decode(try BackupService.encode(backup)), into: ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 3)
        #expect(batches.allSatisfy { $0.code.isEmpty })
    }
}

/// A restored store has to look the way a launch would leave it, and a launch
/// leaves every batch with a code.
@Suite("Restore – batch code", .serialized)
@MainActor
struct RestoreBatchCodeTests: RestoreTestCase {

    @Test func perform_BackupWrittenBeforeBatchCodes_CodesEveryBatch() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(Batch.mock(recipeName: "Lavender"))
        ctx.insert(Batch.mock(recipeName: "Rose"))
        try ctx.save()
        var backup = try BackupService.makeBackup(from: ctx)
        for index in backup.batches.indices {
            backup.batches[index].code = nil
        }
        let coordinator = makeCoordinator()

        await restore(backup, with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 2)
        #expect(batches.allSatisfy { BatchCodeGenerator.generatedStem(of: $0.code) != nil })
        #expect(Set(batches.map(\.code)).count == 2)
    }

    @Test func perform_BackupWithCodes_KeepsThem() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(Batch.mock(code: "2026/14", recipeName: "Lavender"))
        try ctx.save()
        let coordinator = makeCoordinator()

        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        let batch = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(batch.code == "2026/14")
    }
}
