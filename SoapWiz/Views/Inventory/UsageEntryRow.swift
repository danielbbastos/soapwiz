import SwiftUI

/// One usage-history row on the ingredient or purchase detail screen. Tapping
/// it jumps to the batch that made the deduction, on the History tab.
struct UsageEntryRow: View {
    let entry: UsageEntry

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showBatch(entry.batch)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.batch.recipeName)
                            .foregroundStyle(.primary)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("−\(entry.amount.formatted(.number.precision(.fractionLength(0...2)))) \(entry.unit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if !entry.sourceLabels.isEmpty {
                    Text("From \(entry.sourceLabels.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
