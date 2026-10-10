import SwiftUI

/// One capsule chip in a horizontal filter row, drawn as the ledger's chip:
/// honey and amber when selected, a ruled outline on the raised sheet when not.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    /// Drawn after the title.
    let count: Int?
    /// Drawn before the title when unselected.
    let dot: Color?
    let action: () -> Void

    init(
        _ title: String,
        isSelected: Bool,
        count: Int? = nil,
        dot: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.count = count
        self.dot = dot
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityTitle: String {
        guard let count else { return title }
        return "\(title), \(count)"
    }

    /// Drawn about 36pt tall, with the padding that brings the hit area to 44
    /// outside the capsule so the chip doesn't look any bigger.
    private var label: some View {
        HoneyLedgerChip(title: title, isSelected: isSelected, count: count, dot: dot)
            .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
