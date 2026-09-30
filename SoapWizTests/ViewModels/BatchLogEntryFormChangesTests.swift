import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// Whether closing the entry form would throw work away, which decides if the
/// sheet can be swiped down and if Cancel asks first.
@Suite("Batch log entry form — unsaved changes", .serialized)
@MainActor
struct BatchLogEntryFormChangesTests {

    private func newForm() -> BatchLogEntryFormViewModel {
        BatchLogEntryFormViewModel(batch: Batch(recipe: nil, recipeName: "Castile", batchCount: 1))
    }

    @Test func hasChanges_NewFormUntouched_IsFalse() {
        #expect(!newForm().hasChanges)
    }

    @Test func hasChanges_NewFormWithANote_IsTrue() {
        let sut = newForm()

        sut.text = "Poured"

        #expect(sut.hasChanges)
    }

    @Test func hasChanges_OnlyWhitespaceTyped_IsFalse() {
        let sut = newForm()

        sut.text = "  \n"

        #expect(!sut.hasChanges)
    }

    @Test func hasChanges_DateMoved_IsTrue() throws {
        let sut = newForm()

        sut.date = try BatchLogFixture.date(day: -3)

        #expect(sut.hasChanges)
    }

    @Test func hasChanges_PhotoAddedThenRemoved_IsFalse() async throws {
        let sut = newForm()
        sut.addPhoto(try await BatchLogFixture.photoData())

        sut.removePhoto(try #require(sut.photos.first))

        #expect(!sut.hasChanges)
    }

    @Test func hasChanges_ExistingEntryUntouched_IsFalse() async throws {
        let (container, ctx) = try BatchLogFixture.makeContext()
        _ = container
        let batch = BatchLogFixture.insertBatch(ctx)
        let entry = BatchLogFixture.insertEntry(
            ctx, batch: batch, date: try BatchLogFixture.date(day: 0), text: "Cut",
            photos: [try await BatchLogFixture.photoData()]
        )
        try ctx.save()

        let sut = BatchLogEntryFormViewModel(batch: batch, entry: entry)

        #expect(!sut.hasChanges)
    }

    @Test func hasChanges_ExistingEntryPhotoRemoved_IsTrue() async throws {
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

        #expect(sut.hasChanges)
    }

    // MARK: - Library load problems

    @Test func loadProblem_NoFailures_IsNil() {
        #expect(BatchLogEntryFormViewModel.loadProblem(failures: 0, of: 3) == nil)
    }

    @Test func loadProblem_SomeFailed_DiffersFromAllFailed() throws {
        let some = try #require(BatchLogEntryFormViewModel.loadProblem(failures: 1, of: 3))
        let all = try #require(BatchLogEntryFormViewModel.loadProblem(failures: 3, of: 3))

        #expect(some != all)
    }

    @Test func loadProblem_SinglePhotoFailed_IsTheAllFailedMessage() {
        #expect(
            BatchLogEntryFormViewModel.loadProblem(failures: 1, of: 1)
                == BatchLogEntryFormViewModel.loadProblem(failures: 4, of: 4)
        )
    }
}
