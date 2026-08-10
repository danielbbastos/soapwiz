import SwiftUI

/// The star shown on a list row. Drawn even when the row isn't a favourite —
/// faintly, so a long list stays quiet — because it is the only affordance that
/// says favouriting exists at all. The leading swipe is the shortcut for people
/// who already know.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
        }
        // Without this the whole row's `NavigationLink` swallows the tap and
        // pushes the detail screen instead of toggling.
        .buttonStyle(.borderless)
        .accessibilityLabel(isFavorite ? "Remove from Favourites" : "Add to Favourites")
    }
}

extension View {
    /// The fast path for people who already know favouriting exists. Lives here so
    /// the two lists can't drift apart on wording; the star is the discoverable
    /// path, and SwiftUI exposes this to VoiceOver as a custom action.
    func favoriteSwipeAction(isFavorite: Bool, toggle: @escaping () -> Void) -> some View {
        swipeActions(edge: .leading) {
            Button(isFavorite ? "Unfavourite" : "Favourite",
                   systemImage: isFavorite ? "star.slash" : "star",
                   action: toggle)
                .tint(.yellow)
        }
    }
}
