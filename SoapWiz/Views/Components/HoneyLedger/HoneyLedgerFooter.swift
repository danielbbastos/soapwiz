import SwiftUI

/// A list section's footer: one note in footnote `inkSoft`.
struct HoneyLedgerFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.inkSoft)
    }
}
