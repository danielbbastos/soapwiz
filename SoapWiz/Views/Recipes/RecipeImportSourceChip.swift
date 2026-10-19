import SwiftUI

/// The ledger's unselected chip, with a glyph where the chip's dot would be.
/// Fades to `inkFaint` while disabled, since its colours are its own and a
/// plain button style won't dim them.
struct RecipeImportSourceChip: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(isEnabled ? Color.inkSoft : Color.inkFaint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.paperRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(isEnabled ? Color.ruleStrong : Color.rule, lineWidth: 1))
    }
}
