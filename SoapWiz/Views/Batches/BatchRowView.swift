import SwiftUI

struct BatchRowView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let batch: Batch

    private var cost: String? {
        guard batch.tracksInventory && batch.totalCost > 0 else { return nil }
        return batch.totalCost.formatted(.currency(code: currencyCode))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.vertical, 2)
    }

    /// One column at the accessibility sizes: beside the name, the trailing
    /// figure would squeeze it until it broke mid-word.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            details
            BatchCureStatusLine(status: batch.cureStatus)
            trailingFigure(alignment: .leading, keepsWhole: false)
        }
    }

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            HStack(alignment: .center, spacing: 12) {
                details
                Spacer()
                // Each line kept whole. Only the code and date share width
                // with it, so the name and the stamp keep the full row.
                trailingFigure(alignment: .trailing, keepsWhole: true)
            }
            BatchCureStatusLine(status: batch.cureStatus)
        }
    }

    private var title: some View {
        Text(batch.recipeName)
            .font(.headline)
            .foregroundStyle(Color.ink)
    }

    /// The code and the date, each on a line of its own.
    @ViewBuilder
    private var details: some View {
        let code = BatchCodeGenerator.trimmed(batch.code)
        VStack(alignment: .leading, spacing: 4) {
            if !code.isEmpty {
                Text(code)
                    .font(.subheadline.monospaced())
            }
            // No year: the month header above the row already carries it.
            Text(batch.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                .font(.subheadline)
        }
        .foregroundStyle(Color.inkSoft)
    }

    /// How many batches the run made, with what it cost under it when that was
    /// recorded. Several batches label the price a total, so it isn't read as
    /// the price of one.
    private func trailingFigure(alignment: HorizontalAlignment, keepsWhole: Bool) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            figureLine(
                Text("^[\(batch.batchCount) batch](inflect: true)")
                    .font(.subheadline.monospacedDigit()),
                keepsWhole: keepsWhole
            )
            if let cost {
                figureLine(
                    (batch.batchCount > 1 ? Text("Total \(cost)") : Text(cost))
                        .font(.subheadline.weight(.medium).monospacedDigit()),
                    keepsWhole: keepsWhole
                )
            }
        }
        .foregroundStyle(Color.inkSoft)
    }

    @ViewBuilder
    private func figureLine(_ text: Text, keepsWhole: Bool) -> some View {
        if keepsWhole {
            text.lineLimit(1).fixedSize()
        } else {
            text
        }
    }
}
