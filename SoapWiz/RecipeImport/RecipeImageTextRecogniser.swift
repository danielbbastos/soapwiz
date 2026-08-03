import UIKit
import Vision

/// Reads text off a photograph of a recipe.
///
/// The OCR result is fed into exactly the same sanitize-and-extract pipeline as
/// a paste, and it lands in the same editable text field first — a photo of a
/// printed page comes back with the odd misread character, and it is far easier
/// to fix that before extraction than to correct the resulting recipe.
///
/// Vision's `RecognizeTextRequest` is available from iOS 18, so this path needs
/// no version gate of its own beyond the one already on the whole feature.
enum RecipeImageTextRecogniser {
    static func recogniseText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // The orientation has to be passed through: a photo taken in portrait
        // carries its rotation in metadata rather than in the pixel buffer, and
        // Vision reads sideways text badly.
        let observations = try await request.perform(on: cgImage, orientation: image.imageOrientation.cgOrientation)
        return lines(from: observations).joined(separator: "\n")
    }

    /// Reading order, not detection order. Vision returns observations in
    /// whatever order it found them; a recipe's meaning depends on its rows, so
    /// they are sorted top-to-bottom and then left-to-right.
    ///
    /// Coordinates are normalised with the origin at the bottom left, so a
    /// larger `maxY` is higher up the page.
    static func lines(from observations: [RecognizedTextObservation]) -> [String] {
        observations
            .sorted { lhs, rhs in
                let lhsTop = lhs.boundingBox.cgRect.maxY
                let rhsTop = rhs.boundingBox.cgRect.maxY
                if abs(lhsTop - rhsTop) > sameLineTolerance { return lhsTop > rhsTop }
                return lhs.boundingBox.cgRect.minX < rhs.boundingBox.cgRect.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// Two observations whose vertical centres are within this fraction of the
    /// image height are treated as the same row, so a table's columns read
    /// across rather than down.
    private static let sameLineTolerance: CGFloat = 0.01
}

extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
