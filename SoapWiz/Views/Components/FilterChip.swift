import SwiftUI

/// One capsule chip in a horizontal filter row. Selected draws filled in `tint`
/// with a white label; unselected draws on the card surface with a tinted label
/// and a matching border, so an unselected chip still reads as belonging to its
/// filter rather than as disabled.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    init(
        _ title: String,
        isSelected: Bool,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : tint)
                .background(isSelected ? tint : Color.cardBackground, in: .capsule)
                .overlay(Capsule().strokeBorder(tint.opacity(isSelected ? 0 : 0.5)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
