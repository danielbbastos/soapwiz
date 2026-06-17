import SwiftUI
import SwiftData

struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private let additiveUnits = ["g", "kg", "oz", "lb", "ml", "L", "% of batch", "% of liquids", "% of oils"]
private let fragranceUnits = ["g", "oz", "ml", "% of batch", "% of liquids", "% of oils"]

/// Label style with a tighter gap between the icon and title than the default.
private struct TightLabelStyle: LabelStyle {
    var spacing: CGFloat = 4
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

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
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var activePicker: PickerSection?
    @State private var oilsExpanded = true
    @State private var additivesExpanded = true
    @State private var fragrancesExpanded = true
    @State private var calculatedAmountsExpanded = true
    @State private var extraIngredientsExpanded = false
    @State private var selectedSectionAPct: Int = 1
    @State private var showSectionAInfo = false
    @State private var showFragranceInfo = false
    @State private var costBreakdownExpanded = false
    @State private var availableHeight: CGFloat = 0

    var body: some View {
        Form {
            oilsSection
            additivesSection
            fragrancesSection
            calculatedAmountsSection
            extraIngredientsSection
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: AvailableHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(AvailableHeightKey.self) { if !costBreakdownExpanded { availableHeight = $0 } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CostBreakdownBarView(model: model, isExpanded: $costBreakdownExpanded, availableHeight: availableHeight)
        }
        .sheet(isPresented: $showSectionAInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dosage Percentages")
                    .font(.headline)
                (Text("These percentages represent the dosage as a fraction of total oil weight — "
                      + "for example, 1% equals 10 g per 1000 g of oils.\n\nThey are only relevant for ")
                 + Text("Sodium Lactate").bold()
                 + Text(" and ")
                 + Text("Citric Acid Powder").bold()
                 + Text("."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.fraction(0.3)])
            .presentationDragIndicator(.visible)
        }
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
                            .labelStyle(TightLabelStyle())
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
                        TextField("0", value: Binding(
                            get: { draft.amount },
                            set: { model.userEdited(id: draft.id, amount: $0) }
                        ), format: .number.precision(.fractionLength(0...1)))
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
                        .labelStyle(TightLabelStyle())
                }
                ForEach(model.additiveDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        TextField("0", value: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ), format: .number.precision(.fractionLength(0...3)))
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
                HStack {
                    Button {
                        activePicker = .fragrances
                    } label: {
                        Label("Add fragrance", systemImage: "plus")
                            .labelStyle(TightLabelStyle())
                    }
                    Spacer()
                    if let target = model.fragranceTarget {
                        HStack(spacing: 4) {
                            Text(target.text)
                                .foregroundStyle(target.isOverTarget ? Color.red : Color.secondary)
                            Button {
                                showFragranceInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showFragranceInfo) {
                                Text("Recommended fragrance load: \(model.formatPercentage(target.percentage))% of total oils, set on the Config tab.")
                                    .font(.footnote)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: 240)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                }
                ForEach(model.fragranceDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        TextField("0", value: Binding(
                            get: { draft.amount },
                            set: { newVal in
                                if draft.unit == "% of oils" {
                                    model.userEditedFragrance(id: draft.id, amount: newVal)
                                } else {
                                    model.updateFragrance(id: draft.id, amount: newVal)
                                }
                            }
                        ), format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 55)
                        Picker("Unit", selection: Binding(
                            get: { draft.unit },
                            set: { model.updateFragrance(id: draft.id, unit: $0) }
                        )) {
                            ForEach(fragranceUnits, id: \.self) { Text($0) }
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
        .background(Color.cardBackground)
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
        .foregroundStyle(summary ? Color.primary : Color.secondary)
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }

    private func formatPct(_ pct: Double) -> String {
        String(format: "%.1f%%", pct)
    }
}

// MARK: - Extra Ingredients

private extension RecipeIngredientsTabView {
    @ViewBuilder
    var extraIngredientsSection: some View {
        if let data = model.extraIngredientData {
            Section(header: sectionHeader("Extra Ingredients", expanded: $extraIngredientsExpanded)) {
                if extraIngredientsExpanded {
                    extraSectionA(rows: data.sectionA)
                    extraSectionB(rows: data.sectionB)
                }
            }
        }
    }

    private func extraSectionA(rows: [ExtraSectionARow]) -> some View {
        VStack(spacing: 0) {
            extraSectionAHeader
            ForEach(rows) { row in
                Divider().padding(.leading, 16)
                extraSectionARow(label: row.label, weight: value(from: row), isSubrow: false)
                if let naoh = row.naohLye {
                    let naohValue = selectedSectionAPct == 1 ? naoh.val1 : selectedSectionAPct == 2 ? naoh.val2 : naoh.val3
                    extraSectionARow(label: "↳ Extra NaOH", weight: naohValue, isSubrow: true)
                }
                if let koh = row.kohLye {
                    let kohValue = selectedSectionAPct == 1 ? koh.val1 : selectedSectionAPct == 2 ? koh.val2 : koh.val3
                    extraSectionARow(label: "↳ Extra KOH", weight: kohValue, isSubrow: true)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func value(from row: ExtraSectionARow) -> Double {
        switch selectedSectionAPct {
        case 1: row.val1
        case 2: row.val2
        default: row.val3
        }
    }

    private var extraSectionAHeader: some View {
        HStack(spacing: 8) {
            Text("Ingredient")
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Percentage", selection: $selectedSectionAPct) {
                Text("1%").tag(1)
                Text("2%").tag(2)
                Text("3%").tag(3)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Button {
                showSectionAInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .background(Color.cardBackground)
    }

    private func extraSectionARow(label: String, weight: Double, isSubrow: Bool) -> some View {
        let match = isSubrow ? nil : model.matchedExtraIngredient(label: label, in: inventory)
        return extraRow(ingredient: match, amount: weight) {
            HStack(spacing: 8) {
                if !isSubrow {
                    extraToggleIcon(label: label, ingredient: match)
                }
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                Text(formatWeight(weight))
                    .monospacedDigit()
            }
            .padding(.leading, isSubrow ? 32 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .font(.footnote)
            .foregroundStyle(isSubrow ? Color.secondary : Color.primary)
            .italic(isSubrow)
        }
    }

    /// Wraps an extras row in a toggle button when its label matched an
    /// inventory ingredient, so tapping anywhere on the row checks or unchecks
    /// the suggestion. Unmatched (or sub-) rows render as-is.
    @ViewBuilder
    private func extraRow<Content: View>(
        ingredient: Ingredient?, amount: Double, @ViewBuilder content: () -> Content
    ) -> some View {
        if let ingredient {
            Button {
                model.toggleExtra(ingredient, amount: amount)
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    /// Checkmark state for an extras row; the dashed placeholder explains how
    /// to enable rows with no matching inventory ingredient.
    @ViewBuilder
    private func extraToggleIcon(label: String, ingredient: Ingredient?) -> some View {
        if let ingredient {
            let isAdded = model.isExtraAdded(ingredient)
            Image(systemName: isAdded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAdded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        } else {
            InfoPopoverIcon(
                text: "Not in inventory. Add an ingredient matching “\(label)” to include it in the recipe cost.",
                systemImage: "circle.dashed"
            )
        }
    }

    private func extraSectionB(rows: [ExtraSectionBRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Divider().padding(.leading, 16)
                extraSectionBRow(row)
                if let naoh = row.naohLye {
                    extraSectionBSubRow("↳ Extra NaOH", value: naoh)
                }
                if let koh = row.kohLye {
                    extraSectionBSubRow("↳ Extra KOH", value: koh)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func extraSectionBRow(_ row: ExtraSectionBRow) -> some View {
        let match = model.matchedExtraIngredient(label: row.label, in: inventory)
        return extraRow(ingredient: match, amount: row.minValue) {
            HStack(spacing: 8) {
                extraToggleIcon(label: row.label, ingredient: match)
                Text(row.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if let max = row.maxValue {
                    Text("\(formatWeight(row.minValue)) – \(formatWeight(max))")
                        .monospacedDigit()
                } else {
                    Text(formatWeight(row.minValue))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .font(.footnote)
        }
    }

    private func extraSectionBSubRow(_ label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
                .italic()
            Text(formatWeight(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .font(.footnote)
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
