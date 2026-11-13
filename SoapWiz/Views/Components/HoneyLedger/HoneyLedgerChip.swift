import SwiftUI

/// The ledger's capsule chip, drawn about 36pt tall: honey with a check when
/// selected, a ruled outline on the raised sheet when not. A `dot` leads an
/// unselected chip and a `count` trails the title. Not a control on its own;
/// `FilterChip` wraps it in one.
struct HoneyLedgerChip: View {
    let title: String
    var isSelected = false
    var count: Int?
    var dot: Color?
    /// Draws an `xmark` after the title instead of the selected checkmark.
    var isRemovable = false

    var body: some View {
        HStack(spacing: 4) {
            if isSelected && !isRemovable {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 9, height: 9)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkFaint)
            }
            if isRemovable {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.honey : Color.paperRaised, in: .capsule)
        .overlay(Capsule().strokeBorder(isSelected ? Color.amber : Color.ruleStrong, lineWidth: 1))
    }
}
