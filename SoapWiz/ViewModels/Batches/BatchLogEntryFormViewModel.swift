import Foundation
import SwiftData

/// One photo in the form: either a photo the entry already has, or one added
/// in this session and not yet stored.
struct BatchLogPhotoDraft: Identifiable {
    let id = UUID()
    /// The stored photo this draft stands for; nil for a new one.
    let stored: BatchLogPhoto?
    /// `stored`'s identity, read while the photo was certainly alive. Reading
    /// it again later could land on a photo another device has since deleted.
    let storedID: PersistentIdentifier?
    /// The display-size image of a new photo; nil for a stored one, whose file
    /// is left on disk rather than read just to draw a small square.
    let imageData: Data?
    /// What the form draws, and for a new photo the thumbnail it is stored with.
    let previewData: Data?

    init(stored: BatchLogPhoto) {
        self.stored = stored
        self.storedID = stored.persistentModelID
        self.imageData = nil
        self.previewData = stored.thumbnailData
    }

    init(imageData: Data, previewData: Data?) {
        self.stored = nil
        self.storedID = nil
        self.imageData = imageData
        self.previewData = previewData
    }
}

@MainActor
@Observable
final class BatchLogEntryFormViewModel {
    /// Bounds what one entry adds to a sync and to a backup file.
    static let maxPhotos = 10

    var date: Date = .now
    var text: String = ""
    private(set) var photos: [BatchLogPhotoDraft] = []

    /// True while picked photos are still being read and downscaled. Saving
    /// then would store the ones already done and silently drop the rest.
    var isLoadingPhotos = false

    let batch: Batch
    let entry: BatchLogEntry?

    /// Stored photos the user took off, and only those. A photo another device
    /// added to the entry while the form was open was never in the form, and
    /// must not be deleted as if it had been removed.
    private var removedPhotoIDs: Set<PersistentIdentifier> = []

    private let initialDate: Date
    private let initialText: String
    private let initialPhotoIDs: [UUID]

    init(batch: Batch, entry: BatchLogEntry? = nil) {
        let date = entry?.date ?? .now
        let text = entry?.text ?? ""
        let photos = entry?.sortedPhotos.map(BatchLogPhotoDraft.init(stored:)) ?? []
        self.batch = batch
        self.entry = entry
        self.date = date
        self.text = text
        self.photos = photos
        initialDate = date
        initialText = text
        initialPhotoIDs = photos.map(\.id)
    }

    var isEditing: Bool { entry != nil }
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A note, a photo, or both — an entry with neither records nothing.
    var isValid: Bool { !trimmedText.isEmpty || !photos.isEmpty }

    var canSave: Bool { isValid && !isLoadingPhotos }

    /// Whether closing the form now would throw work away. Photos compare by
    /// draft, so adding one and removing it again reads as unchanged.
    var hasChanges: Bool {
        date != initialDate || trimmedText != initialText || photos.map(\.id) != initialPhotoIDs
    }

    var remainingPhotoSlots: Int { max(0, Self.maxPhotos - photos.count) }
    var canAddPhoto: Bool { remainingPhotoSlots > 0 }

    /// Appends a photo already downscaled by `ImageDownscaler`, with the
    /// thumbnail made from it off the main actor. Ignored once the entry is
    /// full, so a library selection larger than the room left fills the entry
    /// and drops the rest.
    func addPhoto(_ imageData: Data, preview: Data?) {
        guard canAddPhoto else { return }
        photos.append(BatchLogPhotoDraft(imageData: imageData, previewData: preview))
    }

    func removePhoto(_ draft: BatchLogPhotoDraft) {
        photos.removeAll { $0.id == draft.id }
        if let storedID = draft.storedID {
            removedPhotoIDs.insert(storedID)
        }
    }

    /// What the photo field says after reading a library selection, or nil
    /// when every photo came through.
    static func loadProblem(failures: Int, of total: Int) -> String? {
        guard failures > 0 else { return nil }
        return failures == total
            ? "Couldn't open that. Try another photo."
            : "Some photos couldn't be opened."
    }

    /// Writes the form onto its entry, or onto a new one on the batch.
    ///
    /// Another device can delete the entry while this form is open. Written to
    /// then, the edit would land on a detached model and vanish, and any new
    /// photo would be linked to nothing; so a deleted entry is saved as a new
    /// one instead. `modelContext` is the only thing read off it to tell: it
    /// is truthful once the row is gone, where `isDeleted` is not, and reading
    /// a stored attribute off a detached model traps (see `LiveIngredient`).
    /// Its stored photos went with it and are skipped the same way — and when
    /// they were all it had, with no note and nothing new, there is nothing
    /// left to record: no entry is made and the result is nil, rather than a
    /// bare date the form would never let anyone save.
    ///
    /// Another device can also add a photo to the entry meanwhile. It stays,
    /// after the photos the form shows: only photos the user removed here are
    /// deleted.
    @discardableResult
    func save(context: ModelContext) -> BatchLogEntry? {
        let kept = photos.filter { $0.stored == nil || $0.stored?.modelContext != nil }
        let target: BatchLogEntry
        if let entry, entry.modelContext != nil {
            target = entry
        } else {
            guard !trimmedText.isEmpty || !kept.isEmpty else { return nil }
            target = BatchLogEntry()
            context.insert(target)
            target.batch = batch
        }
        target.date = date
        target.text = trimmedText

        for photo in target.photos where removedPhotoIDs.contains(photo.persistentModelID) {
            // Unlinked first: a deleted photo otherwise lingers in
            // `target.photos` until the context saves, and the log row
            // redrawn the moment this returns would still show it.
            photo.entry = nil
            context.delete(photo)
        }

        let keptIDs = Set(kept.compactMap(\.storedID))
        let arrived = target.sortedPhotos.filter { !keptIDs.contains($0.persistentModelID) }

        for (position, draft) in kept.enumerated() {
            if let stored = draft.stored {
                stored.position = position
            } else {
                // The draft's preview is the thumbnail already: deriving it
                // again here would redo a decode and an encode per photo on
                // the main actor, just as the sheet closes.
                let photo = BatchLogPhoto(
                    imageData: draft.imageData,
                    thumbnailData: draft.previewData,
                    position: position
                )
                context.insert(photo)
                photo.entry = target
            }
        }
        for (offset, photo) in arrived.enumerated() {
            photo.position = kept.count + offset
        }
        context.saveLoggingFailure()
        return target
    }

    /// Deletes an entry and, by cascade, its photos. Unlinked from its batch
    /// first, for the reason given in `save(context:)`: without it the batch's
    /// screen keeps showing the entry it just deleted.
    ///
    /// Does nothing when another device deleted the entry first — the
    /// confirmation can still be up when that syncs in, and touching the
    /// detached row would trap.
    static func delete(_ entry: BatchLogEntry, context: ModelContext) {
        guard entry.modelContext != nil else { return }
        entry.batch = nil
        context.delete(entry)
        context.saveLoggingFailure()
    }
}
