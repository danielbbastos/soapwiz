import SwiftUI

/// The History tab's occasional reminder to export a backup, for a device whose
/// data isn't mirrored to iCloud.
struct BackupNudgeCard: View {
    let onExport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Back up your data")
                .font(.headline)
                .foregroundStyle(Color.ink)
            HoneyLedgerNote(
                "Your recipes and history are only on this device. Export a backup file to keep them safe."
            )
            HStack(spacing: 12) {
                Button("Export Backup", action: onExport)
                    .buttonStyle(HoneyLedgerPrimaryButtonStyle(isCompact: true))
                Button("Not now", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.inkSoft)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
