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

    /// Tall enough to read a few lines of a recipe at once, short enough that
    /// the buttons underneath stay on screen on the smallest supported phone.
    private let height: CGFloat = 200

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
        }
        .frame(height: height)
    }
}
