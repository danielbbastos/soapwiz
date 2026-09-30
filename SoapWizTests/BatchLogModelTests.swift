import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

@Suite("Batch log – model", .serialized)
@MainActor
struct BatchLogModelTests {

    // MARK: - Accessors

    @Test func logEntries_NewBatch_IsEmpty() {
        let batch = Batch(recipe: nil, recipeName: "Castile", batchCount: 1)

        #expect(batch.logEntries.isEmpty)
        #expect(BatchHistoryViewModel.sortedLogEntries(of: batch).isEmpty)
    }

    @Test func photos_NewEntry_IsEmpty() {
        let entry = BatchLogEntry(text: "Poured")

        #expect(entry.photos.isEmpty)
        #expect(entry.sortedPhotos.isEmpty)
    }

    @Test func logEntries_EntryLinkedFromItsOwnSide_ReadsThroughAccessor() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        try ctx.save()

        #expect(batch.logEntries.map(\.text) == ["Poured"])
    }

    // MARK: - Photo thumbnails

    @Test func photoInit_WithImage_DerivesASmallerThumbnail() async throws {
        let image = try await BatchLogFixture.photoData()

        let photo = BatchLogPhoto(imageData: image, position: 0)

        let thumbnail = try #require(photo.thumbnailData)
        #expect(thumbnail == ImageDownscaler.thumbnail(from: image))
        #expect(thumbnail.count < image.count)
    }

    @Test func photoInit_ThumbnailGiven_KeepsItRatherThanDerivingOne() async throws {
        let image = try await BatchLogFixture.photoData()
        let thumbnail = Data("already made".utf8)

        let photo = BatchLogPhoto(imageData: image, thumbnailData: thumbnail, position: 0)

        #expect(photo.thumbnailData == thumbnail)
    }

    @Test func photoInit_NilImage_HasNoThumbnail() {
        let photo = BatchLogPhoto(imageData: nil, position: 0)

        #expect(photo.thumbnailData == nil)
    }

    @Test func photoInit_DataThatIsNotAnImage_HasNoThumbnail() {
        let photo = BatchLogPhoto(imageData: Data("not an image".utf8), position: 0)

        #expect(photo.thumbnailData == nil)
    }

    // MARK: - Order

    @Test func sortedLogEntries_MultipleEntries_OrdersOldestFirst() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 2), text: "Cut")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 1), text: "Unmoulded")
        try ctx.save()

        let sorted = BatchHistoryViewModel.sortedLogEntries(of: batch)

        #expect(sorted.map(\.text) == ["Poured", "Unmoulded", "Cut"])
    }

    @Test func sortedLogEntries_SameDate_OrdersByText() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let date = try BatchLogFixture.date(day: 0)
        BatchLogFixture.insertEntry(ctx, batch: batch, date: date, text: "B")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: date, text: "A")
        try ctx.save()

        let sorted = BatchHistoryViewModel.sortedLogEntries(of: batch)

        #expect(sorted.map(\.text) == ["A", "B"])
    }

    @Test func sortedPhotos_OutOfOrderPositions_OrdersByPosition() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut")
        for position in [2, 0, 1] {
            BatchLogFixture.insertPhoto(ctx, entry: entry, imageData: nil, position: position)
        }
        try ctx.save()

        #expect(entry.sortedPhotos.map(\.position) == [0, 1, 2])
    }

    // MARK: - Delete rules

    @Test func deleteBatch_CascadesToLogEntriesAndPhotos() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()

        ctx.delete(batch)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).isEmpty)
    }

    @Test func deleteEntry_CascadesToPhotosAndKeepsBatchAndOtherEntries() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let doomed = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 1), text: "Unmoulded",
            photos: [try await BatchLogFixture.photoData(.systemBlue)]
        )
        try ctx.save()

        ctx.delete(doomed)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
        #expect(batch.logEntries.map(\.text) == ["Unmoulded"])
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).count == 1)
    }

    @Test func deletePhoto_KeepsItsEntry() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()

        ctx.delete(try #require(entry.photos.first))
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).count == 1)
        #expect(entry.photos.isEmpty)
    }

    /// Batch history outlives its recipe, and the log goes wherever the batch does.
    @Test func deleteRecipe_KeepsBatchAndItsLog() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        let batch = BatchLogFixture.insertBatch(ctx, recipe: recipe)
        BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let survivor = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(survivor.recipe == nil)
        #expect(survivor.logEntries.map(\.text) == ["Poured"])
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).count == 1)
    }
}
