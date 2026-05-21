import SwiftUI
import SwiftData

private let additiveUnits = ["g", "kg", "ml", "L", "oz", "% of batch", "% of liquids", "% of oils"]

private enum PickerSection: String, Identifiable {
    case oils, additives, fragrances
    var id: String { rawValue }

    var role: RecipeIngredientRole {
        switch self {
        case .oils: return .oil
        case .additives: return .additive
        case .fragrances: return .fragrance
        }
    }
}

struct RecipeIngredientsTabView: View {
    @Bindable var model: RecipeFormViewModel
    @State private var activePicker: PickerSection?
    @State private var oilsExpanded = true
    @State private var additivesExpanded = true
    @State private var fragrancesExpanded = true
    @State private var calculatedAmountsExpanded = true
    @State private var productsExpanded = true

    var body: some View {
        Form {
            oilsSection
            additivesSection
            fragrancesSection
            calculatedAmountsSection
            if !model.oilDrafts.isEmpty {
                productsSection
            }
        }
        .scrollClipDisabled()
        .sheet(item: $activePicker) { section in
            IngredientPickerView(
                addedIDs: addedIDs(for: section),
                allowedRole: section.role,
                onSelect: selectAction(for: section)
            )
        }
    }

    // MARK: - Collapsible header

    private func sectionHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                    .animation(.easeInOut(duration: 0.2), value: expanded.wrappedValue)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Oils

    private var oilsSection: some View {
        Section(header: sectionHeader(IngredientCategory.Name.oils, expanded: $oilsExpanded)) {
            if oilsExpanded {
                HStack {
                    Button {
                        activePicker = .oils
                    } label: {
                        Label("Add oil", systemImage: "plus")
                    }
                    Spacer()
                    if model.weightUnitIsPercentage && !model.oilDrafts.isEmpty {
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
                            get: { draft.amount },
                            set: { model.userEdited(id: draft.id, amount: $0) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        Text(model.weightUnitIsPercentage ? "%" : model.weightUnit)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { model.removeOil(at: $0) }
            }
        }
    }

    // MARK: - Additives

    private var additivesSection: some View {
        Section(header: sectionHeader(IngredientCategory.Name.additives, expanded: $additivesExpanded)) {
            if additivesExpanded {
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
    }

    // MARK: - Fragrances

    private var fragrancesSection: some View {
        Section(header: sectionHeader(IngredientCategory.Name.fragrances, expanded: $fragrancesExpanded)) {
            if fragrancesExpanded {
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
    }

    // MARK: - Calculated amounts

    @ViewBuilder
    private var calculatedAmountsSection: some View {
        if let rows = model.calculatedAmountRows {
            Section(header: sectionHeader("Calculated amounts", expanded: $calculatedAmountsExpanded)) {
                if calculatedAmountsExpanded {
                    VStack(spacing: 0) {
                        amountHeader
                        ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                            Divider().padding(.leading, row.isSummary ? 0 : 16)
                            amountRow(row.label, weight: row.weight, pct: row.pct, summary: row.isSummary)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    private var amountHeader: some View {
        HStack(spacing: 8) {
            Text("Ingredient")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Weight")
                .frame(width: 90, alignment: .trailing)
            Text("%")
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func amountRow(_ label: String, weight: Double, pct: Double, summary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(formatWeight(weight))
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
            Text(formatPct(pct))
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(.footnote)
        .fontWeight(summary ? .medium : .regular)
        .foregroundStyle(summary ? Color.secondary : Color.primary)
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }

    private func formatPct(_ pct: Double) -> String {
        String(format: "%.1f%%", pct)
    }

    // MARK: - Products

    private var productsSection: some View {
        Section(header: sectionHeader("Products", expanded: $productsExpanded)) {
            if productsExpanded { ScrollViewReader { proxy in
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
            } // if productsExpanded
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

}
