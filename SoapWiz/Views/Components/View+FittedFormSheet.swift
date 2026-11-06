import SwiftUI
import UIKit

/// The height a form sheet takes (SW-314): as tall as its content, up to a cap
/// that leaves a margin above and below.
enum FittedSheetHeight {
    /// Each of the top and bottom margins, as a share of the available height.
    static let marginFraction: CGFloat = 0.15

    /// `nil` while either input is unusable, so the sheet keeps the system's
    /// own form height until there is something to fit.
    static func height(content: CGFloat?, available: CGFloat) -> CGFloat? {
        guard let content, content > 0, available > 0 else { return nil }
        let cap = available * (1 - 2 * marginFraction)
        return min(content, cap)
    }
}

/// `.form` with its height replaced by the root's ideal height, which
/// `fitsSheetToContent()` sets to `FittedSheetHeight`'s result, or to zero
/// while there is none. The system reads a sizing again only when the root's
/// size changes, so the height travels as the root's ideal size and not as a
/// value held here. `.fitted` can't be used as is: a `Form` has no finite
/// height of its own, so it would collapse.
///
/// With `minimumIsForm`, the sheet is never shorter than the system's form
/// height, which is what `.form` proposes.
struct ContentFittedSizing: PresentationSizing {
    var minimumIsForm = false

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let proposal = FormPresentationSizing.form.proposedSize(for: root, context: context)
        let fitted = root.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        guard fitted.height > 0 else { return proposal }
        var height = fitted.height
        if minimumIsForm, let formHeight = proposal.height {
            height = max(height, formHeight)
        }
        return ProposedViewSize(width: proposal.width, height: height)
    }
}

extension EnvironmentValues {
    /// The height of the window, safe areas included, which a sheet is centred
    /// in. Zero until the first measurement.
    @Entry var windowHeight: CGFloat = 0
}

extension View {
    /// Sizes the sheet to the content of the `Form` inside this view, up to
    /// `FittedSheetHeight`'s cap. Apply it to the sheet's root (the
    /// `NavigationStack`: a sizing set inside it never reaches the sheet), whose
    /// form's content height must not depend on the sheet's own height.
    ///
    /// With `fixedAtOpen`, the height is taken from the first usable
    /// measurement (after the keyboard hides, if it is up then) and never
    /// updated, and the sheet is at least the system's form height. For a sheet
    /// whose content changes constantly, such as the shopping list: resizing
    /// as rows come and go made the sheet jump. The content scrolls inside.
    func fitsSheetToContent(fixedAtOpen: Bool = false) -> some View {
        modifier(FittedFormSheetModifier(fixedAtOpen: fixedAtOpen))
    }

    /// Publishes the window's height to every sheet below, for `fitsSheetToContent()`.
    func publishesWindowHeight() -> some View {
        modifier(WindowHeightModifier())
    }
}

private struct FittedFormSheetModifier: ViewModifier {
    @Environment(\.windowHeight) private var windowHeight

    @State private var contentHeight: CGFloat?

    /// The latest measurement, kept while the keyboard is up so the sheet can
    /// catch up with it once the keyboard is gone.
    @State private var measuredHeight: CGFloat?

    @State private var isKeyboardShown = false

    let fixedAtOpen: Bool

    /// Whether a fixed-at-open sheet already has a usable height.
    private var holdsOpenHeight: Bool {
        fixedAtOpen && (contentHeight ?? 0) > 0
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                (geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom).rounded()
            } action: { _, height in
                measuredHeight = height
                // The keyboard grows the bottom inset, which would stretch the
                // sheet behind it: the height holds while it is up. If the
                // keyboard is already up at the first measurement (a sheet that
                // focuses a field as it opens), the sheet keeps the system form
                // height until the keyboard hides.
                guard !isKeyboardShown, !holdsOpenHeight else { return }
                contentHeight = height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardShown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isKeyboardShown = false
                guard !holdsOpenHeight else { return }
                contentHeight = measuredHeight
            }
            .frame(idealHeight: FittedSheetHeight.height(content: contentHeight, available: windowHeight) ?? 0)
            .presentationSizing(ContentFittedSizing(minimumIsForm: fixedAtOpen))
    }
}

private struct WindowHeightModifier: ViewModifier {
    @State private var windowHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
                    } action: { windowHeight = $0 }
            }
            .environment(\.windowHeight, windowHeight)
    }
}
