import SwiftUI

/// The multi-line box a recipe is pasted into.
///
/// A `TextField(axis: .vertical)` was the obvious choice and the wrong one: it
/// grows to fit its content instead of scrolling, so a long paste inflated the
/// row until the buttons below it were pushed off the screen entirely, and any
/// trailing blank lines showed up as dead space nothing could fill.
///
/// A fixed-height `TextEditor` scrolls its own content, which keeps the rest of
/// the form reachable no matter how much is pasted.
struct RecipeTextInputView: View {
    @Binding var text: String
    var isEnabled: Bool = true

    /// Bumped whenever the text is replaced from outside the field — a paste, a
    /// photo, a scan, a clear.
    ///
    /// `TextEditor` keeps the laid-out size it had when text is swapped
    /// underneath it, so importing a second image left the box scrolling over
    /// the old content height: the new text was there but sat below a band of
    /// blank space, and the visible portion stayed clipped to the previous
    /// length. Rebuilding on a revision that only changes for programmatic
    /// writes forces a fresh layout without rebuilding on every keystroke.
    var revision: Int = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Regular in both axes means iPad, where the sheet has room to show more
    /// of the recipe at once. Everything else keeps the compact height, which
    /// has to leave the buttons and the action below it on screen.
    private var height: CGFloat {
        horizontalSizeClass == .regular && verticalSizeClass == .regular ? 320 : 200
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Paste the recipe here")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .disabled(!isEnabled)
                .accessibilityLabel("Recipe text")
                .id(revision)
        }
        .frame(height: height)
    }
}
