import SwiftUI
import SwiftData

private let additiveUnits = ["g", "kg", "ml", "L", "oz", "% of batch", "% of liquids", "% of oils"]

private enum PickerSection: String, Identifiable {
    case oils, additives, fragrances
    var id: String { rawValue }

    var allowedCategories: [String] {
        switch self {
        case .oils: return ["Oils", "Waxes", "Fats"]
        case .additives: return ["Additives", "Others"]
        case .fragrances: return ["Fragrances"]
        }
    }
}

struct RecipeIngredientsTabView: View {
    @Bindable var model: RecipeFormViewModel
    @State private var activePicker: PickerSection?

    var body: some View {
        Form {
            oilsSection
            additivesSection
            fragrancesSection
            if let calculations = model.oilAmountCalculations {
                calculatedAmountsSection(calculations)
            }
            if !model.oilDrafts.isEmpty {
                productsSection
            }
        }
        .scrollClipDisabled()
        .sheet(item: $activePicker) { section in
            IngredientPickerView(
                addedIDs: addedIDs(for: section),
                allowedCategories: section.allowedCategories,
                onSelect: selectAction(for: section)
            )
        }
    }

    // MARK: - Oils

    private var oilsSection: some View {
        Section("Oils") {
            HStack {
                Button {
                    activePicker = .oils
                } label: {
                    Label("Add oil", systemImage: "plus")
                }
                Spacer()
                if !model.oilDrafts.isEmpty {
                    Text(model.totalPercentageText)
                        .foregroundStyle(abs(model.totalPercentage - 100) < 0.1 ? Color.green : Color.red)
                        .frame(width: 60, alignment: .trailing)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.oilDrafts) { draft in
                HStack {
                    Text(draft.ingredient.name)
                    Spacer()
                    TextField("0", text: Binding(
                        get: { draft.percentage },
                        set: { model.userEdited(id: draft.id, percentage: $0) }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { model.removeOil(at: $0) }
        }
    }

    // MARK: - Additives

    private var additivesSection: some View {
        Section("Additives") {
            Button {
                activePicker = .additives
            } label: {
                Label("Add additive", systemImage: "plus")
            }
            ForEach(model.additiveDrafts) { draft in
                HStack {
                    Text(draft.ingredient.name)
                        .lineLimit(1)
                    Spacer()
                    TextField("0", text: Binding(
                        get: { draft.amount },
                        set: { model.updateAdditive(id: draft.id, amount: $0) }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 55)
                    Picker("Unit", selection: Binding(
                        get: { draft.unit },
                        set: { model.updateAdditive(id: draft.id, unit: $0) }
                    )) {
                        ForEach(additiveUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .onDelete { model.removeAdditive(at: $0) }
        }
    }

    // MARK: - Fragrances

    private var fragrancesSection: some View {
        Section("Fragrances") {
            Button {
                activePicker = .fragrances
            } label: {
                Label("Add fragrance", systemImage: "plus")
            }
            ForEach(model.fragranceDrafts) { draft in
                HStack {
                    Text(draft.ingredient.name)
                        .lineLimit(1)
                    Spacer()
                    TextField("0", text: Binding(
                        get: { draft.amount },
                        set: { model.updateFragrance(id: draft.id, amount: $0) }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 55)
                    Picker("Unit", selection: Binding(
                        get: { draft.unit },
                        set: { model.updateFragrance(id: draft.id, unit: $0) }
                    )) {
                        ForEach(additiveUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .onDelete { model.removeFragrance(at: $0) }
        }
    }

    // MARK: - Calculated amounts

    @ViewBuilder
    private func calculatedAmountsSection(_ calculations: [OilAmountCalculation]) -> some View {
        Section("Calculated amounts") {
            Grid(alignment: .leading, horizontalSpacing: 12) {
                GridRow {
                    Text("Oil")
                        .fontWeight(.medium)
                    Text("Weight")
                        .fontWeight(.medium)
                        .gridColumnAlignment(.trailing)
                    Text("NaOH")
                        .fontWeight(.medium)
                        .gridColumnAlignment(.trailing)
                }
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                ForEach(calculations) { calc in
                    GridRow {
                        Text(calc.ingredient.name)
                            .lineLimit(1)
                        Text(formatGrams(calc.weightGrams))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(formatGrams(calc.lyeGrams))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
                if let totalLye = model.calculatedLyeAmount,
                   let totalWater = model.calculatedWaterAmount {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("NaOH total")
                            .fontWeight(.medium)
                        Text("")
                            .gridColumnAlignment(.trailing)
                        Text(formatGrams(totalLye))
                            .fontWeight(.medium)
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Text("Water")
                            .fontWeight(.medium)
                        Text(formatGrams(totalWater))
                            .fontWeight(.medium)
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.footnote)
        }
    }

    // MARK: - Products

    private var productsSection: some View {
        Section("Products") {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach($model.productDrafts) { $draft in
                            let result = model.breakdownAndCost(for: draft)
                            RecipeProductCardView(
                                draft: $draft,
                                breakdown: result.breakdown,
                                totalCost: result.total,
                                availableUnits: IngredientUnit.allCases
                            )
                            .containerRelativeFrame(.horizontal)
                            .id(draft.id)
                        }
                        AddProductCardView {
                            model.addProduct(defaultUnitSymbol: IngredientUnit.grams.rawValue)
                            if let newID = model.productDrafts.last?.id {
                                withAnimation { proxy.scrollTo(newID) }
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id("addButton")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
            }
            .listRowInsets(EdgeInsets())

            if !model.productDrafts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0...model.productDrafts.count, id: \.self) { _ in
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Helpers

    private func addedIDs(for section: PickerSection) -> Set<PersistentIdentifier> {
        switch section {
        case .oils: Set(model.oilDrafts.map(\.ingredient.persistentModelID))
        case .additives: Set(model.additiveDrafts.map(\.ingredient.persistentModelID))
        case .fragrances: Set(model.fragranceDrafts.map(\.ingredient.persistentModelID))
        }
    }

    private func selectAction(for section: PickerSection) -> ([Ingredient]) -> Void {
        switch section {
        case .oils: { ingredients in ingredients.forEach { self.model.addOil($0) } }
        case .additives: { ingredients in ingredients.forEach { self.model.addAdditive($0) } }
        case .fragrances: { ingredients in ingredients.forEach { self.model.addFragrance($0) } }
        }
    }

    private func formatGrams(_ value: Double) -> String {
        if value == 0 { return "0 g" }
        if value < 1 { return String(format: "%.2f g", value) }
        if value < 100 { return String(format: "%.1f g", value) }
        return String(format: "%.0f g", value)
    }
}
