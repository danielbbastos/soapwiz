import SwiftUI
import UIKit

/// The leading image well on a recipe list row.
///
/// Drawn whether or not there is a photo, so every row's text starts at the same
/// x — a list where only some rows are indented reads as damaged rather than
/// sparse.
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
    /// SW-116 will pass `recipe.thumbnailData` here. Until then it is always
    /// nil and every row shows the placeholder.
    var imageData: Data?

    /// The row picks this: a phone row gives the well less room than an iPad
    /// row, because the text beside it has far less width to spare.
    var side: CGFloat = 80

    /// Kept in proportion so the well reads as the same shape at either size —
    /// a fixed radius looks far rounder on the smaller square.
    private var cornerRadius: CGFloat { side * 0.175 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: side, height: side)
            .overlay { content }
            // After the overlay, so it crops the photo rather than only the well.
            .clipShape(shape)
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
                .font(.title)
                .foregroundStyle(Color.accentColor.opacity(0.55))
        }
    }
}
