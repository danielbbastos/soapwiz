import SwiftUI

struct FormulaRowView: View {
    let formula: Formula

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formula.name)
                .font(.body)
            Text("\(formula.ingredients.count) ingredient\(formula.ingredients.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
