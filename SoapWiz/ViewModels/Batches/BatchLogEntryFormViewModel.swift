import Foundation
import SwiftData

/// One photo in the form: either a photo the entry already has, or one added
/// in this session and not yet stored.
struct BatchLogPhotoDraft: Identifiable {
    let id = UUID()
    /// The stored photo this draft stands for; nil for a new one.
    let stored: BatchLogPhoto?
    /// The display-size image of a new photo; nil for a stored one, whose file
    /// is left on disk rather than read just to draw a small square.
    let imageData: Data?
    /// What the form draws.
    let previewData: Data?

    init(stored: BatchLogPhoto) {
        self.stored = stored
        self.imageData = nil
        self.previewData = stored.thumbnailData
    }

    init(imageData: Data) {
        self.stored = nil
        self.imageData = imageData
        self.previewData = ImageDownscaler.thumbnail(from: imageData)
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

    init(batch: Batch, entry: BatchLogEntry? = nil) {
        self.batch = batch
        self.entry = entry
        if let entry {
            date = entry.date
            text = entry.text
            photos = entry.sortedPhotos.map(BatchLogPhotoDraft.init(stored:))
        }
    }

    var isEditing: Bool { entry != nil }
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A note, a photo, or both — an entry with neither records nothing.
    var isValid: Bool { !trimmedText.isEmpty || !photos.isEmpty }

    var canSave: Bool { isValid && !isLoadingPhotos }

    var remainingPhotoSlots: Int { max(0, Self.maxPhotos - photos.count) }
    var canAddPhoto: Bool { remainingPhotoSlots > 0 }

    /// Appends a photo already downscaled by `ImageDownscaler`. Ignored once
    /// the entry is full, so a library selection larger than the room left
    /// fills the entry and drops the rest.
    func addPhoto(_ imageData: Data) {
        guard canAddPhoto else { return }
        photos.append(BatchLogPhotoDraft(imageData: imageData))
    }

    func removePhoto(_ draft: BatchLogPhotoDraft) {
        photos.removeAll { $0.id == draft.id }
    }

    /// Writes the form onto its entry, or onto a new one on the batch.
    ///
    /// Another device can delete the entry while this form is open. Written to
    /// then, the edit would land on a detached model and vanish, and any new
    /// photo would be linked to nothing; so a deleted entry is saved as a new
    /// one instead. `modelContext` is the only thing read off it to tell: it
    /// is truthful once the row is gone, where `isDeleted` is not, and reading
    /// a stored attribute off a detached model traps (see `LiveIngredient`).
    /// Its stored photos went with it and are skipped the same way.
    @discardableResult
    func save(context: ModelContext) -> BatchLogEntry {
        let target: BatchLogEntry
        if let entry, entry.modelContext != nil {
            target = entry
        } else {
            target = BatchLogEntry()
            context.insert(target)
            target.batch = batch
        }
        target.date = date
        target.text = trimmedText

        let kept = photos.filter { $0.stored == nil || $0.stored?.modelContext != nil }
        let keptIDs = Set(kept.compactMap { $0.stored?.persistentModelID })
        for photo in target.photos where !keptIDs.contains(photo.persistentModelID) {
            // Unlinked first: a deleted photo otherwise lingers in
            // `target.photos` until the context saves, and the log row
            // redrawn the moment this returns would still show it.
            photo.entry = nil
            context.delete(photo)
        }
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
        return target
    }

    /// Deletes an entry and, by cascade, its photos. Unlinked from its batch
    /// first, for the reason given in `save(context:)`: without it the batch's
    /// screen keeps showing the entry it just deleted.
    static func delete(_ entry: BatchLogEntry, context: ModelContext) {
        entry.batch = nil
        context.delete(entry)
    }
}
