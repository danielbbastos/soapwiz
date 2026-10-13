import SwiftUI
import UIKit

/// The read-only chemistry block for an oil: SAP values, fatty acid profile and
/// types, and the soap qualities chart. The SAP figures stand on their own; the
/// composition and qualities need a profile, and are replaced by a note when
/// the oil has none yet. Emits nothing for an ingredient that isn't an oil.
/// Emits `Section`s, so it must sit directly inside a `List`.
struct IngredientChemistrySections: View {
    /// Which end of the block the SAP figures sit at. The ingredient's own page
    /// leads with them; a quick look from the picker leads with what the oil
    /// does to a bar, and keeps the lye figures for last.
    enum Order {
        case sapFirst
        case qualitiesFirst
    }

    let ingredient: Ingredient
    var order: Order = .sapFirst

    /// The collapsible sections currently open; all start expanded.
    @State private var expandedSections: Set<ChemistrySection> = Set(ChemistrySection.allCases)

    private enum ChemistrySection: CaseIterable {
        case sapValues, fattyAcidProfile, fattyAcidTypes, soapQualities
    }

    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    private func isExpanded(_ section: ChemistrySection) -> Bool {
        expandedSections.contains(section)
    }

    /// Draws the row's share of the ledger sheet, from where it sits among the
    /// rows its section actually shows.
    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    /// A tappable section header with a rotating chevron. Used instead of the
    /// `Section(isExpanded:)` API, whose disclosure control doesn't render under
    /// the ledger background styling.
    ///
    /// `animated` is off for the iPad's side-by-side columns: they share one
    /// list row, and the list resizes a row around content already laid out at
    /// its new height, so an animated fold makes the other column jump.
    private func collapsibleHeader(_ title: String, _ section: ChemistrySection, animated: Bool = true) -> some View {
        Button {
            withAnimation(animated ? .easeInOut(duration: 0.2) : nil) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        } label: {
            HoneyLedgerSectionLabel(title, isExpanded: isExpanded(section))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var body: some View {
        let chemistry = IngredientChemistry(ingredient: ingredient)
        if let stats = chemistry.stats {
            let hasProfile = chemistry.hasFattyAcidProfile
            switch order {
            case .sapFirst:
                sapSection(stats: stats, hasProfile: hasProfile)
                compositionSections(stats: stats, hasProfile: hasProfile, qualitiesFirst: false)
            case .qualitiesFirst:
                compositionSections(stats: stats, hasProfile: hasProfile, qualitiesFirst: true)
                sapSection(stats: stats, hasProfile: hasProfile)
            }
        }
    }

    /// The composition block: the profile and types with the qualities chart
    /// when there's a profile, or a note saying there isn't one. `qualitiesFirst`
    /// puts the chart ahead of the acid tables.
    @ViewBuilder
    private func compositionSections(stats: RecipeStats, hasProfile: Bool, qualitiesFirst: Bool) -> some View {
        if !hasProfile {
            compositionNoteSection
        } else if qualitiesFirst {
            qualitiesSection(stats: stats)
            profileAndTypesSections(stats: stats)
        } else {
            profileAndTypesSections(stats: stats)
            qualitiesSection(stats: stats)
        }
    }

    private func sapSection(stats: RecipeStats, hasProfile: Bool) -> some View {
        Section {
            if isExpanded(.sapValues) {
                // INS rides with the qualities chart when there's a profile;
                // without one there is no chart, so it belongs here or nowhere.
                let rowCount = hasProfile ? 2 : 3
                sheetRow(0, of: rowCount) { sapRow("SAP (NaOH)", ingredient.sapValue) }
                sheetRow(1, of: rowCount) { sapRow("SAP (KOH)", ingredient.kohSapValue) }
                if !hasProfile {
                    sheetRow(2, of: rowCount) {
                        HoneyLedgerLabeledRow("INS") {
                            Text.honeyLedgerFigure(
                                (stats.ins ?? 0).formatted(.number.precision(.fractionLength(1)))
                            )
                        }
                    }
                }
            }
        } header: {
            collapsibleHeader(hasProfile ? "SAP Values" : "SAP & INS Values", .sapValues)
        }
    }

    private var compositionNoteSection: some View {
        Section {
            sheetRow(0, of: 1) {
                Text(RecipeStatsCopy.ingredientNoFattyAcidData)
                    .foregroundStyle(Color.inkSoft)
            }
        } header: {
            HoneyLedgerSectionLabel("Composition")
        }
    }

    @ViewBuilder
    private func profileAndTypesSections(stats: RecipeStats) -> some View {
        if Self.isPhone {
            Section {
                if isExpanded(.fattyAcidProfile) {
                    sheetRow(0, of: 1) {
                        VStack(spacing: 10) { FattyAcidBreakdownRows(stats: stats) }
                            .padding(.vertical, 4)
                    }
                }
            } header: {
                collapsibleHeader("Fatty Acid Profile", .fattyAcidProfile)
            }

            Section {
                if isExpanded(.fattyAcidTypes) {
                    sheetRow(0, of: 1) {
                        VStack(spacing: 10) { FattyAcidTotalsRows(stats: stats) }
                            .padding(.vertical, 4)
                    }
                }
            } header: {
                collapsibleHeader("Fatty Acid Types", .fattyAcidTypes)
            }
        } else {
            fattyAcidColumnsSection(stats: stats)
        }
    }

    private func qualitiesSection(stats: RecipeStats) -> some View {
        Section {
            if isExpanded(.soapQualities) {
                sheetRow(0, of: 1) {
                    VStack(alignment: .leading, spacing: 12) {
                        SoapPropertiesSection(stats: stats, interactive: false)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            collapsibleHeader("Soap Qualities", .soapQualities)
        }
    }

    /// The profile and the types side by side on iPad: the labels never
    /// change and are short.
    private func fattyAcidColumnsSection(stats: RecipeStats) -> some View {
        Section {
            HoneyLedgerColumns {
                HoneyLedgerColumn(isExpanded: isExpanded(.fattyAcidProfile)) {
                    collapsibleHeader("Fatty Acid Profile", .fattyAcidProfile, animated: false)
                } rows: {
                    FattyAcidBreakdownRows(stats: stats)
                }
            } trailing: {
                HoneyLedgerColumn(isExpanded: isExpanded(.fattyAcidTypes)) {
                    collapsibleHeader("Fatty Acid Types", .fattyAcidTypes, animated: false)
                } rows: {
                    FattyAcidTotalsRows(stats: stats)
                }
            }
        }
    }

    private func sapRow(_ title: String, _ value: Double?) -> some View {
        HoneyLedgerLabeledRow(title) {
            if let value {
                Text.honeyLedgerFigure(
                    value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                    unit: "g/g"
                )
            } else {
                Text("Not specified")
                    .font(.body)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }
}
