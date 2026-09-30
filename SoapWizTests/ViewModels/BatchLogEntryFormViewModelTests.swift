import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

@Suite("BatchLogEntryFormViewModel", .serialized)
@MainActor
struct BatchLogEntryFormViewModelTests {

    // MARK: - Initial state

    @Test func init_NewEntry_StartsEmptyAndInvalid() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        #expect(!sut.isEditing)
        #expect(sut.text.isEmpty)
        #expect(sut.photos.isEmpty)
        #expect(!sut.isValid)
    }

    @Test func init_ExistingEntry_LoadsDateTextAndPhotosInOrder() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let first = try await BatchLogFixture.photoData()
        let second = try await BatchLogFixture.photoData(.systemBlue)
        let date = try BatchLogFixture.date(day: 3)
        let entry = BatchLogFixture.insertEntry(ctx, batch: batch, date: date, text: "Cut", photos: [first, second])
        try ctx.save()

        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)

        #expect(sut.isEditing)
        #expect(sut.date == date)
        #expect(sut.text == "Cut")
        #expect(sut.photos.compactMap { $0.stored?.imageData } == [first, second])
        #expect(sut.photos.allSatisfy { $0.previewData != nil })
    }

    // MARK: - Validity

    @Test func isValid_WhitespaceOnlyText_IsFalse() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        sut.text = "  \n "

        #expect(!sut.isValid)
    }

    @Test func isValid_TextWithoutPhotos_IsTrue() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        sut.text = "Poured at light trace"

        #expect(sut.isValid)
    }

    @Test func isValid_PhotoWithoutText_IsTrue() async throws {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        sut.addPhoto(try await BatchLogFixture.photoData())

        #expect(sut.isValid)
    }

    /// Saving while picked photos are still loading would keep the ones done
    /// so far and drop the rest.
    @Test func canSave_ValidButPhotosStillLoading_IsFalse() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
        sut.text = "Poured"

        sut.isLoadingPhotos = true

        #expect(sut.isValid)
        #expect(!sut.canSave)
    }

    @Test func canSave_ValidAndNothingLoading_IsTrue() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
        sut.text = "Poured"

        #expect(sut.canSave)
    }

    @Test func canSave_Invalid_IsFalse() {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        #expect(!sut.canSave)
    }

    // MARK: - Photo drafts

    @Test func addPhoto_NewPhoto_AppendsADraftWithAPreview() async throws {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
        let image = try await BatchLogFixture.photoData()

        sut.addPhoto(image)

        let draft = try #require(sut.photos.first)
        #expect(sut.photos.count == 1)
        #expect(draft.stored == nil)
        #expect(draft.imageData == image)
        #expect(draft.previewData == ImageDownscaler.thumbnail(from: image))
    }

    @Test func addPhoto_AtTheLimit_IsIgnored() async throws {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
        let image = try await BatchLogFixture.photoData()
        for _ in 0..<BatchLogEntryFormViewModel.maxPhotos { sut.addPhoto(image) }
        #expect(!sut.canAddPhoto)
        #expect(sut.remainingPhotoSlots == 0)

        sut.addPhoto(image)

        #expect(sut.photos.count == BatchLogEntryFormViewModel.maxPhotos)
    }

    @Test func remainingPhotoSlots_OnePhotoAdded_IsOneBelowTheLimit() async throws {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))

        sut.addPhoto(try await BatchLogFixture.photoData())

        #expect(sut.remainingPhotoSlots == BatchLogEntryFormViewModel.maxPhotos - 1)
        #expect(sut.canAddPhoto)
    }

    @Test func removePhoto_OneOfTwo_LeavesTheOther() async throws {
        let sut = BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
        let kept = try await BatchLogFixture.photoData(.systemBlue)
        sut.addPhoto(try await BatchLogFixture.photoData())
        sut.addPhoto(kept)

        sut.removePhoto(try #require(sut.photos.first))

        #expect(sut.photos.map(\.imageData) == [kept])
    }

    // MARK: - Saving a new entry

    @Test func save_NewEntry_InsertsItOnTheBatchWithTrimmedText() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let sut = BatchLogEntryFormViewModel(batch: batch)
        let date = try BatchLogFixture.date(day: 1)
        sut.date = date
        sut.text = "  Unmoulded, still soft\n"

        sut.save(context: ctx)
        try ctx.save()

        let saved = try #require(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).first)
        #expect(saved.batch === batch)
        #expect(saved.date == date)
        #expect(saved.text == "Unmoulded, still soft")
        #expect(batch.logEntries.count == 1)
    }

    /// The batch's screen is open behind the form and redraws the moment the
    /// form closes, well before the context autosaves.
    @Test func save_NewEntry_IsOnTheBatchBeforeTheContextSaves() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch)
        sut.text = "Poured"
        sut.addPhoto(try await BatchLogFixture.photoData())

        let saved = try #require(sut.save(context: ctx))

        #expect(batch.logEntries.map(\.text) == ["Poured"])
        #expect(saved.photos.count == 1)
    }

    @Test func save_NewEntryWithPhotos_StoresThemInOrderWithThumbnails() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let sut = BatchLogEntryFormViewModel(batch: batch)
        let first = try await BatchLogFixture.photoData()
        let second = try await BatchLogFixture.photoData(.systemBlue)
        sut.addPhoto(first)
        sut.addPhoto(second)

        let saved = try #require(sut.save(context: ctx))
        try ctx.save()

        #expect(saved.sortedPhotos.map(\.imageData) == [first, second])
        #expect(saved.sortedPhotos.map(\.position) == [0, 1])
        #expect(saved.sortedPhotos.allSatisfy { $0.thumbnailData != nil })
    }

    // MARK: - Saving an edit

    @Test func save_ExistingEntry_UpdatesItInPlace() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        let newDate = try BatchLogFixture.date(day: 2)
        sut.date = newDate
        sut.text = "Poured at medium trace"

        sut.save(context: ctx)
        try ctx.save()

        let entries = try ctx.fetch(FetchDescriptor<BatchLogEntry>())
        #expect(entries.count == 1)
        #expect(entry.text == "Poured at medium trace")
        #expect(entry.date == newDate)
    }

    @Test func save_ExistingEntryUnchanged_KeepsItsPhotosWithoutDuplicating() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let image = try await BatchLogFixture.photoData()
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut", photos: [image]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)

        sut.save(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).count == 1)
        #expect(entry.sortedPhotos.map(\.imageData) == [image])
    }

    @Test func save_PhotoRemovedWhileEditing_DeletesItAndRenumbersTheRest() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let removed = try await BatchLogFixture.photoData()
        let kept = try await BatchLogFixture.photoData(.systemBlue)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut", photos: [removed, kept]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.removePhoto(try #require(sut.photos.first))

        sut.save(context: ctx)

        #expect(entry.sortedPhotos.map(\.imageData) == [kept])
        try ctx.save()
        let stored = try ctx.fetch(FetchDescriptor<BatchLogPhoto>())
        #expect(stored.map(\.imageData) == [kept])
        #expect(stored.map(\.position) == [0])
    }

    @Test func save_PhotoAddedWhileEditing_GoesAfterTheExistingOnes() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let existing = try await BatchLogFixture.photoData()
        let added = try await BatchLogFixture.photoData(.systemBlue)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut", photos: [existing]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.addPhoto(added)

        sut.save(context: ctx)
        try ctx.save()

        #expect(entry.sortedPhotos.map(\.imageData) == [existing, added])
        #expect(entry.sortedPhotos.map(\.position) == [0, 1])
    }

    @Test func save_NewPhoto_KeepsTheThumbnailTheDraftAlreadyMade() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let sut = BatchLogEntryFormViewModel(batch: batch)
        sut.addPhoto(try await BatchLogFixture.photoData())
        let preview = try #require(sut.photos.first?.previewData)

        let saved = try #require(sut.save(context: ctx))

        #expect(saved.photos.first?.thumbnailData == preview)
    }

    // MARK: - Deleting

    /// The batch's screen redraws as soon as the confirmation closes, before
    /// the context saves, and must not still list the entry.
    @Test func delete_Entry_LeavesTheBatchBeforeTheContextSaves() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let doomed = BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 1), text: "Cut")
        try ctx.save()

        BatchLogEntryFormViewModel.delete(doomed, context: ctx)

        #expect(batch.logEntries.map(\.text) == ["Cut"])
    }

    @Test func delete_EntryWithPhotos_RemovesThemFromTheStore() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let doomed = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()

        BatchLogEntryFormViewModel.delete(doomed, context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test func save_AllPhotosRemovedButTextKept_LeavesATextOnlyEntry() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.removePhoto(try #require(sut.photos.first))

        sut.save(context: ctx)
        try ctx.save()

        #expect(sut.isValid)
        #expect(entry.photos.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).isEmpty)
    }
}
