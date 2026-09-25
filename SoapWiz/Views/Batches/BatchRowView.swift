import SwiftUI

struct BatchRowView: View {
    @Environment(\.currencyCode) private var currencyCode
    let batch: Batch

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(batch.recipeName)
                .font(.body.weight(.medium))
            HStack {
                Text(batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("^[\(batch.batchCount) batch](inflect: true)")
                    .monospacedDigit()
                if batch.tracksInventory && batch.totalCost > 0 {
                    Text("\(batch.totalCost.formatted(.currency(code: currencyCode))) total")
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        // Named rather than inherited, as in `IngredientRowView`: a selected row
        // draws its labels white for a tinted fill this list never shows, since
        // every row carries `Color.cardBackground` of its own — and `.secondary`
        // above is a muted version of whatever the foreground happens to be.
        // This list has no selection binding today and so cannot reach that
        // state; the colour is stated so that it stays true if one is ever added.
        .foregroundStyle(Color.primary)
        .padding(.vertical, 2)
    }
}
