import SwiftUI
import UIKit

/// The square well standing in for an ingredient wherever it is listed: its
/// photo when it has one, and its initial on its own colour when it doesn't.
///
/// A letter rather than a generic icon, because the alternative is every
/// unphotographed row carrying the same picture — a column of identical symbols
/// that tells the eye nothing and only pushes the names to the right. The
/// initial plus a colour assigned at creation makes a row recognisable at a
/// glance, and an ingredient keeps that colour for its whole life.
///
/// The well is always a square of a fixed side, and a photo is scaled to fill it
/// and clipped: a user's photo is whatever shape their camera produced, and
/// letting it size the well would give every row a different height, while
/// stretching it to fit would distort the picture.
///
/// Hidden from accessibility on purpose: it carries no information the row's
/// text does not already state.
struct IngredientAvatar: View {
    /// The small copy derived on save, not the display image — a row must never
    /// fault in an external file to draw itself. Nil shows the letter.
    var imageData: Data?

    let letter: String
    let color: AvatarColor

    /// The caller picks it: a list row and a form field give the well very
    /// different amounts of room.
    var side: CGFloat = 44

    /// Stepped rather than proportional: the ledger sets 8 up to 32, 12 at 44,
    /// and a quarter of the side from 64 up.
    private var cornerRadius: CGFloat {
        if side <= 32 { 8 } else if side < 64 { 12 } else { side * 0.25 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var image: UIImage? {
        imageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        shape
            .fill(color.fill)
            .frame(width: side, height: side)
            .overlay { content }
            // After the overlay, so it crops the photo rather than only the well.
            .clipShape(shape)
            // Over the photo too, so a pale picture still has an edge.
            .overlay(shape.strokeBorder(color.tint.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Text(letter)
                // Serif and semibold, to match the ledger's titles. Weight
                // matters more here than it does in a title: the letter carries
                // the contrast on its own now that the well behind it is a wash.
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(color.ink)
                // The well is a fixed square while the letter scales with the
                // user's text size, so at the accessibility sizes it has to be
                // allowed to shrink back into it rather than push it out of
                // shape.
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }
}
