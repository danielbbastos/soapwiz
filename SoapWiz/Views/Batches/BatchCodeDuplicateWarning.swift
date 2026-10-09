import SwiftUI

/// Shown under a batch code when another batch already carries it. Under a
/// field it explains why the code can't be saved; on the batch screen it flags
/// a clash that arrived by sync, which no field had the chance to refuse.
/// In the design system's blocking-note style, like the stock shortage on the
/// create sheet: it blocks saving rather than merely cautioning.
struct BatchCodeDuplicateWarning: View {
    var body: some View {
        HoneyLedgerFieldNote(
            "Another batch already uses this code.",
            tint: .danger,
            font: .subheadline.weight(.semibold)
        )
    }
}
