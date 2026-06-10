import SwiftUI

struct BatchRowView: View {
    let batch: Batch

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(batch.recipeName)
                .font(.headline)
            HStack {
                Text(batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("^[\(batch.batchCount) batch](inflect: true)")
                    .monospacedDigit()
                if batch.totalCost > 0 {
                    Text("\(Self.currencyFormatter.string(from: NSNumber(value: batch.totalCost)) ?? "—") total")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
