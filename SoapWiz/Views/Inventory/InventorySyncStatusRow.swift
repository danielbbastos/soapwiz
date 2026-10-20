import SwiftUI

/// The first row of the Inventory list while an iCloud import is running.
///
/// The list holds back imported rows until the merge that follows the import
/// (`InventoryRows`), so on a new device it can sit unchanged for a while. This
/// says why. It is plain content, not a button: nothing in it is tappable.
struct InventorySyncStatusRow: View {
    static let title = String(localized: "Syncing with iCloud")
    static let detail = String(localized: "Your ingredients and purchases will update when it finishes.")

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .tint(Color.amberText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(Self.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.title). \(Self.detail)")
    }
}
