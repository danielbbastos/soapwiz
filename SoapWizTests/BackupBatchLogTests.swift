import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// Backup coverage for the batch log, and for exporting with photos left out.
@Suite("Backup – batch log and photo option", .serialized)
@MainActor
struct BackupBatchLogTests: BackupTestHelpers {

    // MARK: - Batch log round trip

    @Test func roundTrip_PreservesLogEntriesOldestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let batch = try seededBatch(ctx)
        let poured = try BatchLogFixture.date(day: 0)
        let cut = try BatchLogFixture.date(day: 2)
        BatchLogFixture.insertEntry(ctx, batch: batch, date: cut, text: "Cut")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: poured, text: "Poured")
        try ctx.save()

        try roundTripInPlace(ctx)

        let restored = BatchHistoryViewModel.sortedLogEntries(of: try seededBatch(ctx))
        #expect(restored.map(\.text) == ["Poured", "Cut"])
        #expect(restored.map(\.date) == [poured, cut])
    }

    @Test func roundTrip_PreservesLogPhotosInOrderAndRebuildsThumbnails() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let first = try await BatchLogFixture.photoData()
        let second = try await BatchLogFixture.photoData(.systemBlue)
        BatchLogFixture.insertEntry(
            ctx, batch: try seededBatch(ctx), date: try BatchLogFixture.date(day: 0), text: "Cut",
            photos: [first, second]
        )
        try ctx.save()

        try roundTripInPlace(ctx)

        let entry = try #require(try seededBatch(ctx).logEntries.first)
        #expect(entry.sortedPhotos.map(\.imageData) == [first, second])
        #expect(entry.sortedPhotos.map(\.thumbnailData) == [first, second].map(ImageDownscaler.thumbnail(from:)))
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).count == 2)
    }

    @Test func roundTrip_BatchWithoutALog_StaysWithoutOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        try roundTripInPlace(ctx)

        #expect(try seededBatch(ctx).logEntries.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).isEmpty)
    }

    @Test func export_LogPhoto_DoesNotWriteTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("thumbnailData"))
    }

    // MARK: - Photo option

    @Test func makeBackup_Default_IncludesEveryPhoto() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)

        let backup = try BackupService.makeBackup(from: ctx)

        #expect(backup.ingredients.first?.imageData != nil)
        #expect(backup.recipes.first?.imageData != nil)
        #expect(backup.batches.first?.logEntries.first?.photos.count == 1)
    }

    @Test func makeBackup_WithoutPhotos_LeavesOutIngredientRecipeAndLogPhotos() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)

        let backup = try BackupService.makeBackup(from: ctx, includingPhotos: false)

        #expect(backup.ingredients.first?.imageData == nil)
        #expect(backup.recipes.first?.imageData == nil)
        #expect(backup.batches.first?.logEntries.first?.photos.isEmpty == true)
    }

    @Test func makeBackup_WithoutPhotos_KeepsEverythingElse() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)

        let backup = try BackupService.makeBackup(from: ctx, includingPhotos: false)

        #expect(backup.ingredients.first?.name == "Olive Oil")
        #expect(backup.recipes.first?.name == "Castile")
        #expect(backup.batches.first?.logEntries.map(\.text) == ["Cut"])
    }

    /// An entry that was only photos has nothing left without them; it is left
    /// out rather than restored as a bare date.
    @Test func makeBackup_WithoutPhotos_DropsAnEntryThatWasOnlyPhotos() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)
        BatchLogFixture.insertEntry(
            ctx, batch: try seededBatch(ctx), date: try BatchLogFixture.date(day: 5), text: "",
            photos: [try await BatchLogFixture.photoData(.systemBlue)]
        )
        try ctx.save()

        let without = try BackupService.makeBackup(from: ctx, includingPhotos: false)
        let with = try BackupService.makeBackup(from: ctx)

        #expect(without.batches.first?.logEntries.map(\.text) == ["Cut"])
        #expect(with.batches.first?.logEntries.map(\.text) == ["Cut", ""])
    }

    @Test func restore_BackupMadeWithoutPhotos_RestoresWithNoPhotosOrThumbnails() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx, includingPhotos: false))
        try BackupService.restore(try BackupService.decode(data), into: ctx)

        let ingredient = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(ingredient.imageData == nil)
        #expect(ingredient.thumbnailData == nil)
        #expect(recipe.imageData == nil)
        #expect(recipe.thumbnailData == nil)
        #expect(try seededBatch(ctx).logEntries.map(\.text) == ["Cut"])
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).isEmpty)
    }

    // MARK: - Export flow

    @Test func includesPhotos_NewViewModel_IsOn() {
        #expect(DataTransferViewModel().includesPhotos)
    }

    @Test func export_IncludesPhotosOff_WritesAFileWithoutPhotos() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)
        let sut = DataTransferViewModel()
        sut.includesPhotos = false

        sut.export(from: ctx)

        let file = try #require(sut.exportFile)
        defer { try? FileManager.default.removeItem(at: file.url) }
        let written = try BackupService.decode(try Data(contentsOf: file.url))
        #expect(written.ingredients.first?.imageData == nil)
        #expect(written.recipes.first?.imageData == nil)
        #expect(written.batches.first?.logEntries.first?.photos.isEmpty == true)
    }

    @Test func export_IncludesPhotosOn_WritesAFileWithPhotos() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try await seedPhotographedStore(ctx)
        let sut = DataTransferViewModel()

        sut.export(from: ctx)

        let file = try #require(sut.exportFile)
        defer { try? FileManager.default.removeItem(at: file.url) }
        let written = try BackupService.decode(try Data(contentsOf: file.url))
        #expect(written.ingredients.first?.imageData != nil)
        #expect(written.recipes.first?.imageData != nil)
        #expect(written.batches.first?.logEntries.first?.photos.count == 1)
    }

    // MARK: - Helpers

    private func seededBatch(_ ctx: ModelContext) throws -> Batch {
        try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
    }

    /// The full graph, with a photo on the ingredient, on the recipe, and on
    /// one log entry of the batch.
    private func seedPhotographedStore(_ ctx: ModelContext) async throws {
        seedFullGraph(ctx)
        let image = try await BatchLogFixture.photoData()
        let ingredient = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        ingredient.imageData = image
        ingredient.thumbnailData = ImageDownscaler.thumbnail(from: image)
        let recipe = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        recipe.imageData = image
        recipe.thumbnailData = ImageDownscaler.thumbnail(from: image)
        BatchLogFixture.insertEntry(
            ctx, batch: try seededBatch(ctx), date: try BatchLogFixture.date(day: 0), text: "Cut",
            photos: [image]
        )
        try ctx.save()
    }
}
