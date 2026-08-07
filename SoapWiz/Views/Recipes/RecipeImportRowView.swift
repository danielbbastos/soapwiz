import SwiftUI

/// One reviewed ingredient: what the source called it, how much of it, and what
/// it resolved to in the inventory.
struct RecipeImportRowView: View {
    let row: RecipeImportRow
    let amountText: String
    var onCreate: () -> Void
    var onSkip: () -> Void
    var onUnskip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.imported.name)
                    .strikethrough(row.resolution == .skipped)
                    .foregroundStyle(row.resolution == .skipped ? .secondary : .primary)
                Spacer()
                Text(amountText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            statusLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch row.resolution {
        case .matched(let ingredient):
            Label(ingredient.name, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .skipped:
            HStack {
                Label("Skipped", systemImage: "minus.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Undo", action: onUnskip)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        case .unmatched:
            HStack {
                Label("Not in your inventory", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Add", action: onCreate)
                    .font(.footnote)
                    .buttonStyle(.borderless)
                Button("Skip", action: onSkip)
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
