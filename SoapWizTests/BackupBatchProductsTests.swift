import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A batch's products surviving the backup file (SW-348), and older files
/// without the key restoring as batches with none.
@Suite("Backup – batch products", .serialized)
@MainActor
struct BackupBatchProductsTests: BackupTestHelpers {

    private func seedWithProducts(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        let made = Batch(
            recipe: nil,
            recipeName: "Made",
            batchCount: 2,
            products: [
                BatchProduct(size: 100, unitSymbol: "g", count: 18),
                BatchProduct(size: 4, unitSymbol: "parts of batch", count: 8)
            ]
        )
        ctx.insert(made)
        try ctx.save()
    }

    @Test func roundTrip_PreservesProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedWithProducts(ctx)

        try roundTripInPlace(ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        let made = try #require(batches.first { $0.recipeName == "Made" })
        #expect(made.products.map(\.size) == [100, 4])
        #expect(made.products.map(\.unitSymbol) == ["g", "parts of batch"])
        #expect(made.products.map(\.count) == [18, 8])
    }

    @Test func restore_BackupWithoutKey_RestoresNoProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedWithProducts(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        for index in backup.batches.indices {
            backup.batches[index].products = nil
        }
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        #expect(decoded.batches.allSatisfy { $0.products == nil })

        try BackupService.restore(decoded, into: ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.isEmpty == false)
        #expect(batches.allSatisfy { $0.products.isEmpty })
    }
}
