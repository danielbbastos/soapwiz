import SwiftUI
import UIKit

/// The leading image well on a recipe list row.
///
/// Drawn whether or not there is a photo, so every row's text starts at the same
/// x — a list where only some rows are indented reads as damaged rather than
/// sparse.
///
/// Without a photo it shows a drop rather than the recipe's initial: the
/// ingredient avatars carry initials, and a recipe list drawn the same way is
/// hard to tell apart from the inventory at a glance. The wash still takes a
/// pigment derived from the name, so recipes differ from each other.
///
/// The well is always a square of a fixed side, and the photo is scaled to fill
/// it and clipped. A user's photo is whatever shape their camera produced;
/// letting it size the well would give every row a different height and a
/// ragged text column, and stretching it to fit would distort the picture.
/// Filling and cropping keeps the grid rigid and the image undeformed, at the
/// cost of the edges of a strongly rectangular shot.
///
/// Hidden from accessibility on purpose: it carries no information the row's
/// text does not already state.
struct RecipeRowThumbnail: View {
    /// The recipe's `thumbnailData` — the small copy derived on save, not the
    /// display image. Nil when the recipe has no photo, which shows the
    /// placeholder.
    var imageData: Data?

    let color: AvatarColor

    /// The row picks this: a phone row gives the well less room than an iPad
    /// row, because the text beside it has far less width to spare.
    var side: CGFloat = 80

    /// Stepped like the ingredient avatar's: 12 below 64, a quarter of the side
    /// from there up.
    private var cornerRadius: CGFloat { side < 64 ? 12 : side * 0.25 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "drop.fill")
                .font(.system(size: side * 0.4))
                .foregroundStyle(color.ink)
        }
    }
}
