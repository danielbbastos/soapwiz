import SwiftUI

/// The widest a screen's content grows on iPad (SW-89). Beyond it a row's label
/// and value sit so far apart that the eye loses the line between them: an
/// iPad in landscape put them ~1,100 pt apart.
enum ReadableWidth {
    static let maximum: CGFloat = 700

    /// The horizontal margin that centres content of `maximum` width in
    /// `width`, or `nil` (the system's own margin) when it already fits, as on
    /// every iPhone, in a sheet and in the list column beside a detail.
    ///
    /// `inset` is padding the content already has of its own, taken off the
    /// margin so that content still lines up with the capped rows around it.
    static func margin(for width: CGFloat, inset: CGFloat = 0) -> CGFloat? {
        guard width > maximum else { return nil }
        return max((width - maximum) / 2 - inset, 0)
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
    /// Apply it directly to the `List`, `Form` or `ScrollView`, before any
    /// `.sheet`. The margin reaches every scroll view inside what it modifies,
    /// and a sheet declared inside would inherit a margin sized for the window
    /// behind it.
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
