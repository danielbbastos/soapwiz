import SwiftUI

/// The multi-line box a recipe is pasted into.
///
/// A `TextField(axis: .vertical)` was the obvious choice and the wrong one: it
/// grows to fit its content instead of scrolling, so a long paste inflated the
/// row until the buttons below it were pushed off the screen entirely, and any
/// trailing blank lines showed up as dead space nothing could fill.
///
/// A `TextEditor` held at a set height scrolls its own content, which keeps the
/// rest of the form reachable no matter how much is pasted. The height comes
/// from the form, which gives the box whatever room the screen has spare.
struct RecipeTextInputView: View {
    @Binding var text: String
    var isEnabled: Bool = true
    let height: CGFloat

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

    let onClear: () -> Void

    private static let clearButtonSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Paste the recipe here")
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color.ink)
                .tint(Color.amber)
                .disabled(!isEnabled)
                .accessibilityLabel("Recipe text")
                .padding(.trailing, text.isEmpty ? 0 : Self.clearButtonSize - 8)
                .id(revision)
        }
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.inkSoft)
                        .frame(width: Self.clearButtonSize, height: Self.clearButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!isEnabled)
                .accessibilityLabel("Clear Text")
            }
        }
    }
}
