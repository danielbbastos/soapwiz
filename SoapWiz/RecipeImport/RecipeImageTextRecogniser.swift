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
    /// One recognised box: its text and where it sat on the page.
    struct TextBox {
        let text: String
        let rect: CGRect
    }

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

    static func lines(from observations: [RecognizedTextObservation]) -> [String] {
        rows(of: observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextBox(text: text, rect: observation.boundingBox.cgRect)
        })
    }

    /// Reading order: rows down the page, and the boxes within a row left to
    /// right, joined so a table's columns read across rather than down.
    ///
    /// Boxes are grouped into rows first rather than sorted with a single
    /// comparator. "Within a tolerance of each other" is not a transitive
    /// relation — A can share a row with B, and B with C, while A and C do not
    /// — so using it inside `sorted(by:)` breaks that function's requirement
    /// for a strict weak ordering and lets the result come out in an order
    /// nothing asked for. Assigning each box to a row in a single downward pass
    /// is transitive by construction.
    ///
    /// Order matters more here than it looks: this text goes straight to the
    /// model, so a scrambled row would hand it one ingredient's name against
    /// another's amount with nothing to reveal the swap.
    static func rows(of boxes: [TextBox]) -> [String] {
        var rows: [[TextBox]] = []
        for box in boxes.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let reference = rows.last?.first,
               abs(reference.rect.midY - box.rect.midY) <= sameRowTolerance {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { row in
            row.sorted { $0.rect.minX < $1.rect.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    /// How far apart two boxes' vertical centres can be and still count as one
    /// row, as a fraction of image height. Coordinates are normalised with the
    /// origin at the bottom left, so a larger `midY` is higher up the page.
    private static let sameRowTolerance: CGFloat = 0.012
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
