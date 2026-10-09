import SwiftUI

/// Where a picker row stands: free to pick, picked, or already taken.
enum HoneyLedgerPickerRowState {
    case unselected
    case selected
    /// Already in whatever the picker adds to. Drawn as an outlined circle with a
    /// check, faint and with no honey, so it reads as done rather than as a
    /// choice; a filled disc would weigh more than the faint name beside it.
    case added
}

/// The label of a picker row: the state at the leading edge, then the name. The
/// caller keeps the `Button`, `.disabled` for an added row, and
/// `.ledgerListDetailRow(isSelected:position:)`, so the row's action and its
/// place in the sheet stay with the screen that owns them.
///
/// At accessibility text sizes the name moves under the circle instead of
/// breaking mid-word beside it.
struct HoneyLedgerPickerRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let name: String
    let state: HoneyLedgerPickerRowState

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    circle
                    nameText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    circle
                    nameText
                    Spacer()
                }
            }
        }
        .contentShape(.rect)
    }

    private var circle: some View {
        Image(systemName: symbol)
            .foregroundStyle(circleColor)
            .accessibilityHidden(true)
    }

    private var nameText: some View {
        Text(name)
            .foregroundStyle(state == .added ? Color.inkFaint : Color.ink)
    }

    private var symbol: String {
        switch state {
        case .unselected: "circle"
        case .selected: "checkmark.circle.fill"
        case .added: "checkmark.circle"
        }
    }

    private var circleColor: Color {
        switch state {
        case .unselected: Color.inkSoft
        case .selected: Color.amberText
        case .added: Color.inkFaint
        }
    }
}
