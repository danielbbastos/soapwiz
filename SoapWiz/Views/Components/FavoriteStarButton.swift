import SwiftUI

/// The star shown on a list row, and the only way to favourite from the list.
/// Drawn even when the row isn't a favourite — faintly, so a long list stays
/// quiet — because it is what says favouriting exists at all.
///
/// A leading swipe action was tried and removed: `List` will not apply an
/// in-section row move while it is tearing down a swipe, so the row's
/// destination slot was reserved but left empty for over a second. Toggling
/// from here has no interaction to wait on, and the move animates cleanly.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    let action: () -> Void

    /// Defaults to the size the star has always been, so rows that never asked
    /// for one are untouched. The recipe list passes a larger value: its star
    /// is the row's only accessory now that the chevron is gone, and at body
    /// size it read as an afterthought rather than a control.
    var font: Font = .body

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(font)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
        }
        // Without this the row's own tap target swallows the tap and opens the
        // detail screen instead of toggling.
        .buttonStyle(.borderless)
        .accessibilityLabel(isFavorite ? "Remove from Favourites" : "Add to Favourites")
    }
}
