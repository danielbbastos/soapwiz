import SwiftUI
import UIKit

/// The recipe's photo at the top of its detail screen, run to the left and
/// right edges of the screen and up behind the navigation bar.
///
/// Full bleed rather than a card: this is the one image on the screen and the
/// first thing the user sees, and an inset photo with rounded corners reads as
/// another row of the form rather than as the recipe's own picture.
struct RecipeHeroPhoto: View {
    let image: UIImage
    let size: CGSize

    /// Where the top edge of the page sits, in this view's own coordinates. The
    /// shadow the page casts is drawn here rather than by the page itself, so
    /// that it is clipped to the photo: a shadow is only visible on the surface
    /// receiving it, and beside the photo's rounded corners there is no surface —
    /// only the app's background, where a shadow with nothing above it reads as a
    /// smudge.
    let pageEdge: CGFloat

    /// Matched to the form's own cards, so the photo reads as one more card of
    /// the page rather than as a banner stuck above it. Shared with the page
    /// that slides over the photo, whose top edge takes the same curve.
    static let cornerRadius: CGFloat = 16

    /// Rounded along the bottom only: the other three edges run off the screen,
    /// and a corner radius on an edge the user cannot see would only crop the
    /// photo.
    private var shape: UnevenRoundedRectangle {
        .rect(
            bottomLeadingRadius: Self.cornerRadius,
            bottomTrailingRadius: Self.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) { navigationBarScrim }
            .overlay(alignment: .top) { pageShadow }
            // After the overlays, so it crops the photo rather than only them.
            .clipShape(shape)
            // Carries no information the screen does not already state in words.
            .accessibilityHidden(true)
    }

    /// Casts the page's leading edge onto the photo, which is what makes the page
    /// read as riding over the photo rather than being cut into it.
    ///
    /// A stand-in for the page rather than the page itself: it carries the same
    /// shape and fill, sits at the same place, and is completely covered by the
    /// real page drawn on top of it — so only its shadow is ever seen. Its height
    /// runs past the bottom of the photo so that the shape still exists (and so
    /// still casts) when the page is resting exactly at the photo's bottom edge.
    private var pageShadow: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            topTrailingRadius: Self.cornerRadius,
            style: .continuous
        )
        .fill(Color.warmBackground)
        .frame(height: size.height)
        .shadow(color: .black.opacity(0.22), radius: 8, y: -3)
        .offset(y: pageEdge)
    }

    /// Darkens the top of the photo, where the title and the buttons sit.
    /// Without it their legibility is a property of whatever the user
    /// photographed — the navigation bar is transparent until the screen is
    /// scrolled, and this screen's title is brown on beige.
    private var navigationBarScrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.35), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 140)
        .allowsHitTesting(false)
    }
}

/// Pins a photo behind the top of a scrolling screen and slides the screen's
/// own content up over it.
///
/// The photo cannot be a row of the form: a form's sections clip their contents
/// to the rounded card shape and inset them from the screen's edges, which is
/// exactly the look full bleed exists to avoid. So it is drawn behind the form,
/// and the form reserves a margin above its first section to leave it visible.
///
/// The photo never moves. What moves is the page: an opaque panel the colour of
/// the app's background, whose top edge tracks the scroll and which carries the
/// form's cards up over the photo. Without it the photo would show through every
/// gap between the cards, since the form itself has no background of its own.
///
/// Overscroll is deliberately excluded from that tracking: at the top of the
/// screen the content rubber-bands over a photo that stays put, rather than
/// dragging the page down and opening a gap above it.
struct RecipeHeroHeader: ViewModifier {
    /// Nil leaves the screen exactly as it was — a recipe without a photo keeps
    /// the ordinary layout that starts below the navigation bar.
    let image: UIImage?

    /// Width to height. The caller picks it: a phone and an iPad have very
    /// different widths to fill, and one ratio across both either buries the
    /// recipe below the fold or reduces the photo to a letterbox strip.
    let aspectRatio: CGFloat

    /// Whether the photo currently reaches up behind the navigation bar, so the
    /// screen can colour its title for a photograph while it does and for the
    /// app's own background once it has scrolled away. White type over beige is
    /// as unreadable as brown type over a bright picture.
    @Binding var coversNavigationBar: Bool

    /// Measured rather than assumed. The width decides both the photo's own
    /// frame and the space the form reserves above its first section, and the
    /// two have to agree exactly or the photo is overlapped or trailed by a gap.
    /// The height is what keeps the page reaching the bottom of the screen as it
    /// rides up.
    @State private var container: CGSize = .zero
    @State private var scrolled: CGFloat = 0

    /// Height of the status bar, taken from the window.
    ///
    /// Neither SwiftUI route reports it here: a scroll view absorbs the safe area
    /// into its content insets, so `safeAreaInsets.top` on this view is zero, and
    /// `ScrollGeometry.contentInsets` leaves out content margins, so the inset it
    /// reports is zero too. The window is the one place that still knows.
    @State private var statusBarHeight: CGFloat = 0

    /// An inline navigation bar, below the status bar. A system metric rather
    /// than a guess, and the same on both idioms.
    private static let navigationBarHeight: CGFloat = 44

    /// Breathing room under the photo, so the first card starts below it rather
    /// than against it. Matched to the spacing the form already puts between its
    /// own sections, so the photo reads as one more band of the page.
    private static let spacingBelowPhoto: CGFloat = 16

    private var size: CGSize {
        CGSize(width: container.width, height: container.width / aspectRatio)
    }

    /// What the form reserves above its first section for the photo to show
    /// through. The scroll view's inset is this plus the safe area.
    private var reservedTop: CGFloat { size.height + Self.spacingBelowPhoto }

    /// Where the top edge of the page sits on screen. It starts at the bottom of
    /// the photo — the gap below the photo belongs to the page, not to the
    /// photo, so it travels up with the cards rather than staying behind.
    private var pageTop: CGFloat { size.height - max(0, scrolled) }

    /// The bottom of the navigation bar, measured down from the top of the
    /// screen: the status bar, plus the bar itself.
    private var navigationBarBottom: CGFloat {
        statusBarHeight + Self.navigationBarHeight
    }

    /// Re-read whenever the container is measured, which is also when it can have
    /// changed — a rotation resizes the screen and the status bar together.
    private static func windowStatusBarHeight() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    /// True while the page has yet to reach the navigation bar, which is exactly
    /// while the title is drawn over the photo.
    private func covers(scrolled: CGFloat) -> Bool {
        size.height - max(0, scrolled) > navigationBarBottom
    }

    func body(content: Content) -> some View {
        if let image {
            content
                // The photo's own height plus the gap below it. The scroll
                // offset is measured against this inset, so the photo still
                // sits flush with the top of the screen at rest.
                .contentMargins(.top, reservedTop, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    scrolled = offset
                    coversNavigationBar = covers(scrolled: offset)
                }
                .ignoresSafeArea(edges: .top)
                .background(alignment: .top) {
                    ZStack(alignment: .top) {
                        RecipeHeroPhoto(image: image, size: size, pageEdge: pageTop)
                        page
                    }
                    // The scroll content already starts at the top of the
                    // screen; without this what sits behind it would start below
                    // the navigation bar instead, and the two would disagree by
                    // exactly the height of that bar.
                    .ignoresSafeArea(edges: .top)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    container = size
                    statusBarHeight = Self.windowStatusBarHeight()
                    coversNavigationBar = covers(scrolled: scrolled)
                }
        } else {
            content
        }
    }

    /// The page the form's cards sit on, in the app's own background colour so
    /// that it is indistinguishable from the screen below the photo and hides
    /// the photo completely once it has passed over it.
    ///
    /// Its top edge takes the same curve as the photo's bottom, so the two read
    /// as the same shape whichever one is on top: at rest the photo's rounded
    /// bottom sits above the page's rounded top, and while scrolling the corners
    /// let a sliver of the photo through as the page rides over it.
    ///
    /// Casts no shadow of its own — `RecipeHeroPhoto` draws that, clipped to
    /// itself, so it can only fall where there is a photo to receive it.
    ///
    /// The height grows by however far the page has risen, so its bottom edge
    /// stays pinned to the bottom of the screen. Sized to one screen and merely
    /// offset, that edge climbs into view as the page rises and the photo shows
    /// through the gaps between the cards below it.
    private var page: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: RecipeHeroPhoto.cornerRadius,
            topTrailingRadius: RecipeHeroPhoto.cornerRadius,
            style: .continuous
        )
        .fill(Color.warmBackground)
        .frame(height: max(0, container.height - pageTop))
        .offset(y: pageTop)
    }
}

extension View {
    /// Draws `image` full bleed behind the top of this scrolling screen. Apply
    /// it before any modifier that puts a background of its own behind the
    /// screen, or the photo is hidden by it.
    func recipeHeroHeader(
        image: UIImage?,
        aspectRatio: CGFloat,
        coversNavigationBar: Binding<Bool>
    ) -> some View {
        modifier(
            RecipeHeroHeader(
                image: image, aspectRatio: aspectRatio, coversNavigationBar: coversNavigationBar
            )
        )
    }
}
