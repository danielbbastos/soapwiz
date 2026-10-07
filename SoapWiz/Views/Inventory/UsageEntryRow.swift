import SwiftUI

/// One usage-history row on the ingredient or purchase detail screen. Tapping
/// it jumps to the batch that made the deduction, on the History tab.
struct UsageEntryRow: View {
    let entry: UsageEntry

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shortDate: String {
        let isCurrentYear = Calendar.current.isDate(entry.date, equalTo: .now, toGranularity: .year)
        return isCurrentYear
            ? entry.date.formatted(.dateTime.month(.abbreviated).day())
            : entry.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var detailLine: Text {
        let date = Text(shortDate)
        guard !entry.batch.code.isEmpty else { return date }
        return Text(entry.batch.code).fontDesign(.monospaced) + Text(" · ") + date
    }

    var body: some View {
        Button {
            navigation.showBatch(entry.batch)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // One column at the accessibility sizes: beside the amount, the
                // recipe name would be squeezed until it broke mid-word.
                if dynamicTypeSize.isAccessibilitySize {
                    names
                    amount
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        names
                        Spacer(minLength: 8)
                        amount
                    }
                }
                if !entry.sourceLabels.isEmpty {
                    Text("From \(entry.sourceLabels.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.batch.recipeName)
                .font(.body)
                .foregroundStyle(Color.ink)
            detailLine
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
        }
    }

    private var amount: Text {
        Text.honeyLedgerFigure(
            entry.amount.formatted(.number.precision(.fractionLength(0...2))),
            unit: entry.unit
        )
    }
}
