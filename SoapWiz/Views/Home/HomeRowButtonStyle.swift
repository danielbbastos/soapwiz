import SwiftUI

/// A whole-row button on a Home card's ledger sheet: honey when highlighted,
/// and pressed honey while a finger is down.
struct HomeRowButtonStyle: ButtonStyle {
    private static let sheetCornerRadius: CGFloat = 18

    var isHighlighted = false
    let isLast: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill(isPressed: configuration.isPressed), in: shape)
            .contentShape(Rectangle())
    }

    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat = isLast ? Self.sheetCornerRadius : 0
        return UnevenRoundedRectangle(
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            style: .continuous
        )
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return .honeyPressed }
        return isHighlighted ? .honey : .clear
    }
}
