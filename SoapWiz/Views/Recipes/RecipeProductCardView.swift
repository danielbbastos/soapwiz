import SwiftUI

struct RecipeProductCardView: View {
    @Binding var draft: RecipeProductDraft
    let breakdown: [IngredientProductBreakdown]
    let totalCost: Double
    let availableUnits: [IngredientUnit]

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .autoupdatingCurrent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Size", text: $draft.size)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Picker("Unit", selection: $draft.unitSymbol) {
                    ForEach(availableUnits, id: \.rawValue) { unit in
                        Text(unit.rawValue).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()
            }

            if !breakdown.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(breakdown, id: \.ingredient.persistentModelID) { row in
                        HStack {
                            Text(row.ingredient.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let amountStr = Self.amountFormatter.string(from: NSNumber(value: row.ingredientAmount)) {
                                Text("\(amountStr) \(draft.unitSymbol)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if row.cost > 0, let costStr = Self.currencyFormatter.string(from: NSNumber(value: row.cost)) {
                                Text(costStr)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .trailing)
                            }
                        }
                    }

                    if totalCost > 0 {
                        Divider()
                        HStack {
                            Text("Total")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let costStr = Self.currencyFormatter.string(from: NSNumber(value: totalCost)) {
                                Text(costStr)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct AddProductCardView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add product", systemImage: "plus.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
        .buttonStyle(.plain)
    }
}
