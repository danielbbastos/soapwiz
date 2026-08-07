import SwiftUI
import SwiftData

struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    @State private var costBreakdownExpanded = false
    @State private var availableHeight: CGFloat = 0

    var body: some View {
        Form {
            unresolvedLineItemsSection
            oilsSection
            additivesSection
            fragrancesSection
            calculatedAmountsSection
            RecipeExtraIngredientsSection(model: model)
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
        .sheet(item: $activePicker) { section in
            IngredientPickerView(
                addedIDs: addedIDs(for: section),
                allowedRole: section.role,
                onSelect: selectAction(for: section)
            )
        }
    }

    // MARK: - Unresolved line items

    @ViewBuilder
    private var unresolvedLineItemsSection: some View {
        if model.unresolvedLineItemCount > 0 {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unresolvedLineItemsTitle)
                        Text(unresolvedLineItemsSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var unresolvedLineItemsTitle: String {
        model.unresolvedLineItemCount == 1
            ? "1 ingredient hasn't synced yet and isn't shown here."
            : "\(model.unresolvedLineItemCount) ingredients haven't synced yet and aren't shown here."
    }

    private var unresolvedLineItemsSubtitle: String {
        model.unresolvedLineItemCount == 1
            ? "It will be kept when you save."
            : "They will be kept when you save."
    }

    // MARK: - Oils

    private var oilsSection: some View {
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.oils, expanded: $oilsExpanded)) {
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
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { model.userEdited(id: draft.id, amount: $0) }
                        ))
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
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.additives, expanded: $additivesExpanded)) {
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
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ), fractionLength: 0...3, width: 55)
                        Picker("Unit", selection: Binding(
                            get: { draft.unit },
                            set: { model.updateAdditive(id: draft.id, unit: $0) }
                        )) {
                            ForEach(RecipeUnitOptions.additive, id: \.self) { Text($0) }
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
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.fragrances, expanded: $fragrancesExpanded)) {
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
                            InfoPopoverIcon(
                                text: "Recommended fragrance load: "
                                    + "\(model.formatPercentage(target.percentage))% of total oils, "
                                    + "set on the Config tab."
                            )
                        }
                    }
                }
                ForEach(model.fragranceDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { newVal in
                                if draft.unit == "% of oils" {
                                    model.userEditedFragrance(id: draft.id, amount: newVal)
                                } else {
                                    model.updateFragrance(id: draft.id, amount: newVal)
                                }
                            }
                        ), fractionLength: 0...3, width: 55)
                        Picker("Unit", selection: Binding(
                            get: { draft.unit },
                            set: { model.updateFragrance(id: draft.id, unit: $0) }
                        )) {
                            ForEach(RecipeUnitOptions.fragrance, id: \.self) { Text($0) }
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
            Section(header: CollapsibleSectionHeader(title: "Calculated amounts", expanded: $calculatedAmountsExpanded)) {
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
