import SwiftUI

/// How a `FilterChip` is drawn.
enum FilterChipStyle {
    /// Filled in the tint with a white label when selected.
    case standard
    /// The ledger's chip: honey and amber when selected, a ruled outline on the
    /// raised sheet when not.
    case ledger
}

/// One capsule chip in a horizontal filter row. Selected draws filled in `tint`
/// with a white label; unselected draws on the card surface with a tinted label
/// and a matching border, so an unselected chip still reads as belonging to its
/// filter rather than as disabled. The `.ledger` style ignores `tint`.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let style: FilterChipStyle
    /// Drawn after the title by the `.ledger` style only.
    let count: Int?
    let action: () -> Void

    init(
        _ title: String,
        isSelected: Bool,
        tint: Color = .accentColor,
        style: FilterChipStyle = .standard,
        count: Int? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.tint = tint
        self.style = style
        self.count = count
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            switch style {
            case .standard: standardLabel
            case .ledger: ledgerLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityTitle: String {
        guard style == .ledger, let count else { return title }
        return "\(title), \(count)"
    }

    private var standardLabel: some View {
        Text(title)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : tint)
            .background(isSelected ? tint : Color.cardBackground, in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(isSelected ? 0 : 0.5)))
    }

    /// Drawn about 36pt tall, with the padding that brings the hit area to 44
    /// outside the capsule so the chip doesn't look any bigger.
    private var ledgerLabel: some View {
        HStack(spacing: 4) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.honey : Color.paperRaised, in: .capsule)
        .overlay(Capsule().strokeBorder(isSelected ? Color.amber : Color.ruleStrong, lineWidth: 1))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
