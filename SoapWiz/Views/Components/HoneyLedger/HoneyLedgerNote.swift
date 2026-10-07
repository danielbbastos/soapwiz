import SwiftUI

/// A description or note on its sheet: New York italic, 18 on 26, in `inkSoft`,
/// scaled with Dynamic Type alongside the body style.
///
/// Sized by point rather than by text style: on iOS 26 a font built from the
/// body text style (`.body.italic()`, `.system(.body, design: .serif)`) drops
/// both the italic and the serif design and renders as upright SF Pro, while
/// the same font at a fixed size renders as asked.
struct HoneyLedgerNote: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var lineGap: CGFloat = 4.5

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, design: .serif).italic())
            .lineSpacing(lineGap)
            .foregroundStyle(Color.inkSoft)
    }
}
