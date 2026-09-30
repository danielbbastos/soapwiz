import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// The edit sheet captures its `BatchLogEntry` when it opens. If another device
/// deletes that entry and the deletion syncs in while the sheet is still up,
/// writing to the captured reference would land on a detached model: the edit
/// gone without a trace, and any new photo linked to nothing. If another device
/// adds a photo to it instead, saving must not delete a photo nobody removed.
@Suite("Batch log entry form — stale references", .serialized)
@MainActor
struct BatchLogEntryFormStaleReferenceTests {

    // MARK: - A photo arrives while the form is open

    @Test func save_PhotoArrivedWhileOpen_IsKeptAfterTheFormsPhotos() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let first = try await BatchLogFixture.photoData()
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut", photos: [first]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        let arrived = try await BatchLogFixture.photoData(.systemBlue)
        BatchLogFixture.insertPhoto(ctx, entry: entry, imageData: arrived, position: 1)
        try ctx.save()
        sut.text = "Cut into 8 bars"

        sut.save(context: ctx)
        try ctx.save()

        #expect(entry.sortedPhotos.map(\.imageData) == [first, arrived])
        #expect(entry.sortedPhotos.map(\.position) == [0, 1])
    }

    @Test func save_PhotoRemovedWhileAnotherArrived_DeletesOnlyTheRemovedOne() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let removed = try await BatchLogFixture.photoData()
        let kept = try await BatchLogFixture.photoData(.systemGreen)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut", photos: [removed, kept]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.removePhoto(try #require(sut.photos.first))
        let arrived = try await BatchLogFixture.photoData(.systemBlue)
        BatchLogFixture.insertPhoto(ctx, entry: entry, imageData: arrived, position: 2)
        try ctx.save()

        sut.save(context: ctx)
        try ctx.save()

        #expect(entry.sortedPhotos.map(\.imageData) == [kept, arrived])
        #expect(entry.sortedPhotos.map(\.position) == [0, 1])
        #expect(try ctx.fetch(FetchDescriptor<BatchLogPhoto>()).count == 2)
    }

    // MARK: - The entry is deleted while the form is open

    @Test func save_EntryDeletedWhileOpen_SavesAsANewEntryOnTheBatch() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        let added = try await BatchLogFixture.photoData(.systemBlue)
        sut.text = "Poured at light trace"
        sut.addPhoto(added)

        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()
        #expect(entry.modelContext == nil)

        let saved = try #require(sut.save(context: ctx))
        try ctx.save()

        #expect(saved !== entry)
        #expect(batch.logEntries.map(\.text) == ["Poured at light trace"])
        #expect(saved.sortedPhotos.map(\.imageData) == [added])
        #expect(saved.sortedPhotos.map(\.position) == [0])
    }

    /// The deleted entry's own photos went with it, and the new photo is on
    /// the new entry: nothing is left without a parent.
    @Test func save_EntryDeletedWhileOpen_LeavesNoPhotoWithoutAnEntry() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.addPhoto(try await BatchLogFixture.photoData(.systemBlue))

        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()
        sut.save(context: ctx)
        try ctx.save()

        let photos = try ctx.fetch(FetchDescriptor<BatchLogPhoto>())
        #expect(photos.count == 1)
        #expect(photos.allSatisfy { $0.entry != nil })
        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).count == 1)
    }

    /// An entry that was only photos, edited without a note or a new photo:
    /// once its photos have gone with it, saving would leave a bare date.
    @Test func save_PhotoOnlyEntryDeletedWhileOpen_MakesNoEntry() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.date = try BatchLogFixture.date(day: 1)
        #expect(sut.canSave)

        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()
        let saved = sut.save(context: ctx)
        try ctx.save()

        #expect(saved == nil)
        #expect(batch.logEntries.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).isEmpty)
    }

    /// The same entry with a new photo added still has something to record.
    @Test func save_PhotoOnlyEntryDeletedWhileOpenWithANewPhoto_KeepsTheNewPhoto() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        let added = try await BatchLogFixture.photoData(.systemBlue)
        sut.addPhoto(added)

        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()
        let saved = try #require(sut.save(context: ctx))
        try ctx.save()

        #expect(saved.sortedPhotos.map(\.imageData) == [added])
        #expect(batch.logEntries.count == 1)
    }

    /// The delete confirmation can still be up when another device's delete
    /// of the same entry syncs in. Confirming then must not touch the detached
    /// row, or anything else.
    @Test func delete_EntryAlreadyDeletedElsewhere_LeavesTheRestAlone() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 1), text: "Cut")
        try ctx.save()
        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()

        BatchLogEntryFormViewModel.delete(entry, context: ctx)
        try ctx.save()

        #expect(batch.logEntries.map(\.text) == ["Cut"])
    }

    /// The ordinary path, so the guard above cannot pass by always creating a
    /// new entry.
    @Test func save_EntryStillInTheStore_WritesToIt() throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Poured")
        try ctx.save()
        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)
        sut.text = "Edited"

        let saved = try #require(sut.save(context: ctx))
        try ctx.save()

        #expect(saved === entry)
        #expect(try ctx.fetch(FetchDescriptor<BatchLogEntry>()).map(\.text) == ["Edited"])
    }
}
