import SwiftUI

/// The first row of the Inventory list while a first or catching-up iCloud
/// import is running.
///
/// The list holds back imported rows until the merge that follows the import
/// (`InventoryRows`), so on a new device, or one returning after a long gap, it
/// can sit unchanged for a while. This says why. It is plain content, not a
/// button: nothing in it is tappable.
struct InventorySyncStatusRow: View {
    let notice: SyncNotice

    private var title: String {
        switch notice {
        case .firstSync: String(localized: "Syncing with iCloud")
        case .catchingUp: String(localized: "Updating from iCloud")
        }
    }

    private var detail: String {
        switch notice {
        case .firstSync:
            String(localized: "Your ingredients and purchases will update when it finishes.")
        case .catchingUp:
            String(localized: "Changes from your other devices will appear when it finishes.")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .tint(Color.amberText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}
