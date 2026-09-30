import Foundation
import SwiftData

/// One dated note in a batch's log — the pour, the unmoulding, a cure check —
/// with whatever photos were taken at the time. Unlike the rest of a `Batch`,
/// the log is written after the fact and stays editable.
@Model
final class BatchLogEntry {
    // Inverse and `.cascade` delete rule are declared on `Batch.logEntriesStorage`:
    // an entry belongs to its batch and to nothing else.
    //
    // Not an `init` parameter on purpose. Set before the entry is inserted, the
    // link reaches the batch's side only at the next save, and a screen showing
    // that batch's log is never told; set after, it shows up at once.
    var batch: Batch?

    /// When the thing being recorded happened, which the user can set — an
    /// entry is often written up after the fact.
    var date: Date = Date.now
    var text: String = ""

    /// Optional for CloudKit; read and write through `photos`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, inverse: \BatchLogPhoto.entry)
    var photosStorage: [BatchLogPhoto]? = []

    var photos: [BatchLogPhoto] {
        get { photosStorage ?? [] }
        set { photosStorage = newValue }
    }

    /// The relationship array is unordered; `position` is the order the user
    /// arranged them in.
    var sortedPhotos: [BatchLogPhoto] {
        photos.sorted { $0.position < $1.position }
    }

    init(date: Date = .now, text: String = "") {
        self.date = date
        self.text = text
    }
}
