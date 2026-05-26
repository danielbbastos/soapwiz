import SwiftUI

struct RecipeStatsTabView: View {
    @Bindable var model: RecipeFormViewModel
    @State private var productsExpanded = true

    private var stats: RecipeStats {
        RecipeStats(oilDrafts: model.oilDrafts)
    }

    var body: some View {
        Form {
            productsSection
            propertiesSection
            indicatorsSection
            fattyAcidSection
            calculatedValuesSection
        }
        .scrollClipDisabled()
    }

    private var productsSection: some View {
        Section(header: sectionHeader("Cost breakdown", expanded: $productsExpanded)) {
            if productsExpanded {
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
                        ForEach(0..<model.productDrafts.count, id: \.self) { _ in
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
    }

    private var propertiesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grey bands show the recommended range for each property.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SoapPropertiesChartView(profile: stats.fattyAcidProfile, hasOils: stats.hasOils)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Soap properties")
        }
    }

    @ViewBuilder
    private var indicatorsSection: some View {
        if stats.hasOils {
            Section {
                SoapPropertyIndicatorView(
                    title: "INS",
                    value: stats.ins,
                    recommended: SoapMetric.insRange,
                    scale: SoapMetric.insScale
                )
                SoapPropertyIndicatorView(
                    title: "Iodine",
                    value: stats.iodineValue,
                    recommended: SoapMetric.iodineRange,
                    scale: SoapMetric.iodineScale
                )
            }
        }
    }

    @ViewBuilder
    private var fattyAcidSection: some View {
        if stats.hasOils {
            Section("Fatty acid profile") {
                fattyAcidRow("Lauric", stats.fattyAcidProfile.lauric)
                fattyAcidRow("Myristic", stats.fattyAcidProfile.myristic)
                fattyAcidRow("Palmitic", stats.fattyAcidProfile.palmitic)
                fattyAcidRow("Stearic", stats.fattyAcidProfile.stearic)
                fattyAcidRow("Oleic", stats.fattyAcidProfile.oleic)
                fattyAcidRow("Linoleic", stats.fattyAcidProfile.linoleic)
                fattyAcidRow("Linolenic", stats.fattyAcidProfile.linolenic)
                fattyAcidRow("Ricinoleic", stats.fattyAcidProfile.ricinoleic)
                Divider()
                fattyAcidRow("Saturated", stats.fattyAcidProfile.saturated, emphasis: true)
                fattyAcidRow("Mono-unsaturated", stats.fattyAcidProfile.monoUnsaturated, emphasis: true)
                fattyAcidRow("Poly-unsaturated", stats.fattyAcidProfile.polyUnsaturated, emphasis: true)
            }
        }
    }

    @ViewBuilder
    private var calculatedValuesSection: some View {
        if stats.hasOils {
            Section("Calculated values") {
                statRow("Iodine value", value: stats.iodineValue, fractionDigits: 1)
                statRow("INS", value: stats.ins, fractionDigits: 1)
                statRow("Total NaOH SAP", value: stats.totalNaOHSap, fractionDigits: 4)
                statRow("Total KOH SAP", value: stats.totalKOHSap, fractionDigits: 4)
            }
        }
    }

    private func fattyAcidRow(_ label: String, _ value: Double, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .fontWeight(emphasis ? .semibold : .regular)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
                .foregroundStyle(emphasis ? .primary : .secondary)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(_ label: String, value: Double, fractionDigits: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(fractionDigits)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

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
}
