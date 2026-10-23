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

/// The label of a picker row: the state at the leading edge, then the label,
/// which is the name unless the caller supplies a richer view of its own. The
/// caller keeps the `Button`, `.disabled` for an added row, and
/// `.ledgerListDetailRow(isSelected:position:)`, so the row's action and its
/// place in the sheet stay with the screen that owns them.
///
/// At accessibility text sizes the label moves under the circle instead of
/// breaking mid-word beside it.
struct HoneyLedgerPickerRow<Label: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let state: HoneyLedgerPickerRowState

    private let label: Label

    init(state: HoneyLedgerPickerRowState, @ViewBuilder label: () -> Label) {
        self.state = state
        self.label = label()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    circle
                    label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    circle
                    label
                    Spacer()
                }
            }
        }
        .contentShape(.rect)
        // The circle is hidden from VoiceOver, so an added row would otherwise
        // read only as a dimmed name. No selected trait: the caller's
        // `.ledgerListDetailRow(isSelected:)` adds that for a selected row.
        .accessibilityValue(state == .added ? Text("Already in recipe") : Text(verbatim: ""))
    }

    private var circle: some View {
        Image(systemName: symbol)
            .foregroundStyle(circleColor)
            .accessibilityHidden(true)
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

extension HoneyLedgerPickerRow where Label == Text {
    /// The common row: just a name, faint once it is already taken.
    init(name: String, state: HoneyLedgerPickerRowState) {
        self.init(state: state) {
            Text(name).foregroundStyle(state == .added ? Color.inkFaint : Color.ink)
        }
    }
}
