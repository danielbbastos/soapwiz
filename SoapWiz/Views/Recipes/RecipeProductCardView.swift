import SwiftUI

private enum BreakdownGroupKey: String, CaseIterable {
    case oils, additives, fragrances, lye

    var displayName: String {
        switch self {
        case .oils: "Oils"
        case .additives: "Additives"
        case .fragrances: "Fragrances"
        case .lye: "Lye"
        }
    }

    /// Only additives and fragrances carry a user-chosen unit; oils and lye are
    /// always shown in the oil weight unit.
    var usesEnteredUnit: Bool {
        self == .additives || self == .fragrances
    }
}

struct RecipeProductCardView: View {
    @Binding var draft: RecipeProductDraft
    let breakdown: ProductCostBreakdown
    let availableUnits: [ProductUnit]
    let model: RecipeFormViewModel

    @State private var collapsedGroups: Set<BreakdownGroupKey> = []
    @State private var isUnitPickerPresented = false

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private var groups: [(key: BreakdownGroupKey, rows: [IngredientProductBreakdown])] {
        let pairs: [(BreakdownGroupKey, [IngredientProductBreakdown])] = [
            (.oils, breakdown.oils),
            (.additives, breakdown.additives),
            (.fragrances, breakdown.fragrances),
            (.lye, breakdown.lye)
        ]
        return pairs.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(groups.enumerated()), id: \.element.key) { idx, group in
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(height: 1.5)
                                .padding(.vertical, 2)
                        }
                        groupView(key: group.key, rows: group.rows)
                    }

                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayedUnitLabel: String {
        if selectedUnit == .wholeBatch { return "Whole batch" }
        return draft.unitSymbol.isEmpty ? "—" : draft.unitSymbol
    }

    private var selectedUnit: ProductUnit? {
        ProductUnit(rawValue: draft.unitSymbol)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if selectedUnit?.requiresSize ?? true {
                NumericTextField(prompt: "Size", value: $draft.size, width: 56, alignment: .center)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            }

            Button {
                isUnitPickerPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text(displayedUnitLabel)
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isUnitPickerPresented) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(availableUnits, id: \.rawValue) { unit in
                        Button {
                            draft.unitSymbol = unit.rawValue
                            if unit.requiresSize, draft.size == 0 {
                                draft.size = 1
                            }
                            isUnitPickerPresented = false
                        } label: {
                            HStack {
                                Text(unit.rawValue)
                                    .font(.subheadline)
                                Spacer()
                                if draft.unitSymbol == unit.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .frame(minWidth: 160)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                .presentationBackground(.clear)
                .presentationCompactAdaptation(.popover)
            }

            if breakdown.exceedsBatchWeight {
                Label("over batch", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func groupView(key: BreakdownGroupKey, rows: [IngredientProductBreakdown]) -> some View {
        let isCollapsed = collapsedGroups.contains(key)
        Button {
            if isCollapsed { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if isCollapsed {
                    summaryRow(name: key.displayName, rows: rows)
                        .transition(.identity)
                } else {
                    ForEach(rows, id: \.ingredient.persistentModelID) { row in
                        let display = model.displayedAmount(for: row, usesEnteredUnit: key.usesEnteredUnit)
                        breakdownRow(
                            name: row.ingredient.name,
                            amount: display.amount,
                            unit: display.unit,
                            cost: row.cost,
                            note: display.conversionNote
                        )
                    }
                    .transition(.identity)
                }
            }
            .animation(nil, value: isCollapsed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(name: String, rows: [IngredientProductBreakdown]) -> some View {
        // Collapsed group total uses the oil weight unit, since rows may mix units.
        let totalAmount = rows.reduce(0) { $0 + $1.ingredientAmount }
        let totalCost = rows.reduce(0) { $0 + $1.cost }
        return breakdownRow(name: name, amount: totalAmount, unit: model.displayWeightUnit, cost: totalCost, emphasized: true)
    }

    @ViewBuilder
    private func breakdownRow(
        name: String, amount: Double, unit: String, cost: Double,
        emphasized: Bool = false, note: String? = nil
    ) -> some View {
        let style = emphasized ? Color.primary : Color.secondary
        let weight: Font.Weight = emphasized ? .semibold : .regular
        HStack {
            Text(name)
                .font(.caption)
                .foregroundStyle(style)
                .fontWeight(weight)
            Spacer()
            if let amountStr = Self.amountFormatter.string(from: NSNumber(value: amount)) {
                if let note {
                    InfoPopoverIcon(text: note)
                }
                Text("\(amountStr) \(unit)")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            if cost > 0, let costStr = Self.currencyFormatter.string(from: NSNumber(value: cost)) {
                Text(costStr)
                    .font(.caption)
                    .foregroundStyle(style)
                    .fontWeight(weight)
                    .frame(width: 64, alignment: .trailing)
            }
        }
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
