import SwiftUI

extension View {
    /// Shows the lye safety notice the first time `isRequired` is true, until
    /// the user accepts it.
    ///
    /// The sheet has no way out but "I Understand". A swipe or a tap outside
    /// would let the one screen that states the burn risk be dismissed without
    /// being read, and the app would take that for an answer.
    func lyeSafetyAcknowledgment(isRequired: Bool) -> some View {
        modifier(LyeSafetyAcknowledgmentModifier(isRequired: isRequired))
    }
}

private struct LyeSafetyAcknowledgmentModifier: ViewModifier {
    let isRequired: Bool

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequired, initial: true) { _, required in
                if LyeSafetyAcknowledgment().shouldPresent(makesSoap: required) {
                    isPresented = true
                }
            }
            .sheet(isPresented: $isPresented) {
                LyeSafetySheet {
                    LyeSafetyAcknowledgment().acknowledge()
                    isPresented = false
                }
            }
    }
}

private struct LyeSafetySheet: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            LyeSafetyNoticeView()
                .padding()
                // The sheet's grabber area sits above this, and the badge read
                // as jammed against the top edge without it.
                .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                LyeSafetyDisclaimer()
                // `Color("AccentColor")`, the same gold the rest of the app
                // tints with, rather than `Color.accentColor`, which resolves a
                // shade darker inside the sheet's environment.
                Button(action: onAccept) {
                    Text("I Understand")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color("AccentColor"), in: .capsule)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.warmBackground)
        }
        .background(Color.warmBackground)
        // Accepting is the only way out: see the modifier's note above.
        .interactiveDismissDisabled()
    }
}
