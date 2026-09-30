import SwiftUI

/// Shown under a batch code when another batch already carries it. Under a
/// field it explains why the code can't be saved; on the batch screen it flags
/// a clash that arrived by sync, which no field had the chance to refuse.
/// Red, like the stock shortage on the create sheet: it blocks rather than
/// cautions.
struct BatchCodeDuplicateWarning: View {
    var body: some View {
        Label("Another batch already uses this code.", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    }
}
