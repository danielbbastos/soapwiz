import SwiftUI

/// One reviewed ingredient: what the source called it, how much of it, and what
/// it resolved to in the inventory. At accessibility text sizes the amount
/// moves under the name, and the actions under the stamp, rather than
/// squeezing either into a sliver beside the other.
struct RecipeImportRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let row: RecipeImportRow
    let amountText: String
    var onCreate: () -> Void
    var onSkip: () -> Void
    var onUnskip: () -> Void

    private var isSkipped: Bool { row.resolution == .skipped }

    private var lineLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            lineLayout {
                Text(row.imported.name)
                    .strikethrough(isSkipped)
                    .foregroundStyle(isSkipped ? Color.inkFaint : Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text.honeyLedgerFigure(amountText, numberColor: isSkipped ? .inkFaint : .ink)
                    .layoutPriority(1)
            }
            statusLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch row.resolution {
        case .matched(let ingredient):
            // Not a `Label`: in a list row its icon takes the row's icon
            // column, which opens a gap and pulls the separator in after it.
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                Text(ingredient.name)
            }
            .font(.footnote)
            .foregroundStyle(Color.inkSoft)
        case .skipped:
            lineLayout {
                StatusStamp(word: "Skipped", tone: .neutral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionButton("Undo", color: .amberText, action: onUnskip)
            }
        case .unmatched:
            lineLayout {
                StatusStamp(word: "Not in inventory", tone: .warning, glyph: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 16) {
                    actionButton("Add", color: .amberText, action: onCreate)
                    actionButton("Skip", color: .inkSoft, action: onSkip)
                }
            }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .buttonStyle(.borderless)
    }
}
