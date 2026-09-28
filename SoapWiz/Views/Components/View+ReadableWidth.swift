import SwiftUI

/// The widest a screen's content grows on iPad (SW-89). Beyond it a row's label
/// and value sit so far apart that the eye loses the line between them: an
/// iPad in landscape put them ~1,100 pt apart.
enum ReadableWidth {
    static let maximum: CGFloat = 700

    /// The margin an inset-grouped list keeps on its own on iPad. The cap only
    /// takes over once it would leave more than this, so content never gets
    /// wider, nor closer to the edge, as a window grows past `maximum`: just
    /// over 700 pt, centring alone would leave a margin of a point or two.
    static let systemMargin: CGFloat = 20

    /// The horizontal margin that centres content of `maximum` width in
    /// `width`, or `nil` (the system's own margin) while that margin would be
    /// no wider than `systemMargin`, as on every iPhone, in a sheet and in the
    /// list column beside a detail. At the switch, 740 pt, both give content
    /// exactly `maximum` wide.
    ///
    /// `inset` is padding the content already has of its own, taken off the
    /// margin so that content still lines up with the capped rows around it.
    static func margin(for width: CGFloat, inset: CGFloat = 0) -> CGFloat? {
        let centred = (width - maximum) / 2
        guard centred > systemMargin else { return nil }
        return centred - inset
    }
}

extension View {
    /// Caps this screen's scrolling content at `ReadableWidth.maximum` and
    /// centres it, while the scroll view itself stays full width: content still
    /// slides under the bars, and the scroll indicator stays at the edge.
    ///
    /// Measured on the screen itself rather than set once for the whole app, so
    /// a screen in a narrower container, like a sheet, is left alone.
    ///
    /// The margin reaches every scroll view inside what it modifies. Sheets
    /// don't inherit it: one declared inside a capped list (Add Size in a
    /// recipe's cost breakdown) keeps its own margins on iPadOS 26. Apply it
    /// directly to the `List`, `Form` or `ScrollView` all the same, before any
    /// `.sheet`, so that doesn't have to hold.
    func readableWidth(inset: CGFloat = 0) -> some View {
        modifier(ReadableWidthModifier(inset: inset))
    }
}

private struct ReadableWidthModifier: ViewModifier {
    let inset: CGFloat
    @State private var margin: CGFloat?

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .onGeometryChange(for: CGFloat?.self) { proxy in
                ReadableWidth.margin(for: proxy.size.width, inset: inset)
            } action: { newMargin in
                margin = newMargin
            }
    }
}
