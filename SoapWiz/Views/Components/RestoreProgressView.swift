import SwiftUI

/// Stands in for the whole interface while a restore rebuilds the store. It exists
/// so that nothing holding a soon-to-be-deleted model is on screen during the wipe.
struct RestoreProgressView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Restoring your backup…")
                .font(.headline)
            Text("This only takes a moment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .warmBackground()
    }
}
