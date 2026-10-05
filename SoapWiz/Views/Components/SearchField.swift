import SwiftUI

/// A list's search field, drawn in the content rather than with `.searchable`.
///
/// The system field ends the search when it's cleared on iPad, taking the
/// keyboard with it, and on iPhone (iOS 26) it hides the navigation bar and adds
/// a large close button beside itself while active. Here clearing only empties
/// the text and keeps the field focused, so the next search can be typed
/// straight away (SW-211, SW-212).
struct SearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey

    @FocusState private var isFocused: Bool

    init(_ prompt: LocalizedStringKey, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(.capsule)
        // A tap anywhere on the capsule, not only on the text, starts typing,
        // as it does on the system field.
        .onTapGesture { isFocused = true }
        .glassEffectInteractiveIOS26(in: .capsule)
        .frame(maxWidth: ReadableWidth.maximum)
        .padding(.horizontal)
    }
}

extension View {
    /// A `SearchField` alone under the navigation bar, for a list with no
    /// filter chips to stack below it.
    func searchHeader(_ prompt: LocalizedStringKey, text: Binding<String>, showsList: Bool) -> some View {
        headerStrip(showsList: showsList) {
            SearchField(prompt, text: text)
                .padding(.bottom, 12)
        }
    }
}
