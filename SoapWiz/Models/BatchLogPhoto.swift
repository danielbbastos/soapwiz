import Foundation
import SwiftData

/// One photo attached to a `BatchLogEntry`. A model of its own rather than an
/// array of data on the entry, so each photo is stored and synced as a separate
/// file instead of every photo of an entry travelling as one blob.
@Model
final class BatchLogPhoto {
    // Inverse and `.cascade` delete rule are declared on `BatchLogEntry.photosStorage`.
    // Set after the photo is inserted, for the reason given on `BatchLogEntry.batch`.
    var entry: BatchLogEntry?

    /// The photo at display size, already downscaled by `ImageDownscaler` before
    /// it is assigned. `.externalStorage` keeps it in a file beside the store
    /// rather than in the row, so drawing a batch's log doesn't drag every
    /// photo into memory with it; CloudKit mirrors it as an asset for the same
    /// reason.
    @Attribute(.externalStorage) var imageData: Data?

    /// The log row's copy of `imageData`, made when the photo is created and
    /// never set independently.
    var thumbnailData: Data?

    /// Where the photo sits among its entry's photos.
    var position: Int = 0

    /// `thumbnailData` is for a caller that already made the thumbnail from
    /// this same image, as the entry form does for its preview. Left out, it
    /// is derived here.
    init(imageData: Data?, thumbnailData: Data? = nil, position: Int) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData ?? imageData.flatMap(ImageDownscaler.thumbnail(from:))
        self.position = position
    }
}
