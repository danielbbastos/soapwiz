import UIKit

/// Turns a picked or captured photo into the two sizes the store keeps: one to
/// show on a detail screen, one to draw in a list row.
///
/// Photos arrive at whatever the camera produced — several megapixels and
/// several megabytes each. Stored as they came, one photographed recipe would
/// outweigh the entire rest of the store, every sync would carry it, and a
/// backup file would be too large to move around. Both sizes are re-encoded as
/// JPEG rather than kept in their original format: the source may be HEIC,
/// which not every consumer of a backup file can read, and a screenshot saved
/// as PNG is several times the size of the same picture as JPEG.
enum ImageDownscaler {
    /// Longest edge of the image kept for display. Enough for a full-width hero
    /// on the largest iPad at 2×, and past the point where more pixels stop
    /// being visible on a phone.
    static let heroMaxDimension: CGFloat = 1280

    /// Longest edge of the list thumbnail. The row's well is 80pt, so this
    /// covers it at 3× with room for the crop that filling it costs.
    static let thumbnailMaxDimension: CGFloat = 240

    private static let heroCompression: CGFloat = 0.8

    /// Lower than the hero's: at thumbnail size the artefacts are invisible, and
    /// this copy is the one stored inline in the record rather than as an
    /// external file, so its size is the one that matters to sync.
    private static let thumbnailCompression: CGFloat = 0.7

    nonisolated static func hero(from image: UIImage) -> Data? {
        downscale(image, maxDimension: heroMaxDimension, compression: heroCompression)
    }

    nonisolated static func hero(from data: Data) -> Data? {
        UIImage(data: data).flatMap(hero)
    }

    nonisolated static func thumbnail(from image: UIImage) -> Data? {
        downscale(image, maxDimension: thumbnailMaxDimension, compression: thumbnailCompression)
    }

    /// Derives the list thumbnail from the stored display image, so the two are
    /// always the same picture. Returns `nil` for data that isn't an image,
    /// which is also how a caller clears a thumbnail alongside a removed photo.
    nonisolated static func thumbnail(from data: Data) -> Data? {
        UIImage(data: data).flatMap(thumbnail)
    }

    /// Redraws the image at the target size and encodes the result as JPEG.
    ///
    /// Redrawing rather than re-encoding the existing pixels is what normalises
    /// orientation: a photo taken with the phone rotated carries its rotation as
    /// metadata, and anything that reads the pixel buffer directly shows it on
    /// its side. Drawing applies the rotation before the encode, so the stored
    /// bytes need no metadata to be right way up.
    nonisolated private static func downscale(_ image: UIImage, maxDimension: CGFloat, compression: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // Never upscale: enlarging a small photo costs bytes and adds no detail.
        let ratio = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        // The photo is measured in its own pixels, so the renderer is told to
        // draw one for one. Left at the screen's scale it would multiply the
        // result by 2 or 3 and undo the resize.
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let redrawn = renderer.image { context in
            // JPEG has no alpha channel, so a transparent source composites
            // against whatever the buffer holds. Filling first makes that white
            // rather than black — a picked PNG with a cut-out background comes
            // back looking like a photo on paper, not a photo in a hole.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return redrawn.jpegData(compressionQuality: compression)
    }
}
