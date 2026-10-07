import SwiftUI

/// An amber diamond with a hairline running off to the trailing edge, centred
/// in the same box a `HoneyLedgerSectionLabel` occupies, so a list header made
/// of it sits the same distance from its sheet as a labelled one does.
struct HoneyLedgerOrnament: View {
    var body: some View {
        Text(verbatim: " ")
            .font(.caption.weight(.bold))
            .tracking(0.9)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.amber)
                        .frame(width: 8 / 2.0.squareRoot(), height: 8 / 2.0.squareRoot())
                        .rotationEffect(.degrees(45))
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(Color.rule)
                        .frame(height: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
