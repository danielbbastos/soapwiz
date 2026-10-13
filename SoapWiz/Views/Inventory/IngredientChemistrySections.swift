import SwiftUI
import UIKit

/// The read-only chemistry block for an oil: SAP values, fatty acid profile and
/// types, and the soap qualities chart. The SAP figures stand on their own; the
/// composition and qualities need a profile, and are replaced by a note when
/// the oil has none yet. Emits nothing for an ingredient that isn't an oil.
/// Emits `Section`s, so it must sit directly inside a `List`.
struct IngredientChemistrySections: View {
    let ingredient: Ingredient

    /// Whether the profile, types and SAP values may sit side by side on iPad.
    /// Off where the screen is narrow, such as the picker's pushed sheet.
    var prefersColumns: Bool = true

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
            if hasProfile {
                qualitiesSection(stats: stats)
                profileTypesAndSapSections(stats: stats)
            } else {
                compositionNoteSection
                sapSection(stats: stats, hasProfile: false)
            }
        }
    }

    private func sapSection(stats: RecipeStats, hasProfile: Bool) -> some View {
        Section {
            if isExpanded(.sapValues) {
                // INS rides with the qualities bars when there's a profile;
                // without one there are no bars, so it belongs here or nowhere.
                let rowCount = hasProfile ? 2 : 3
                sheetRow(0, of: rowCount) { sapRow("SAP (NaOH)", ingredient.sapValue) }
                sheetRow(1, of: rowCount) { sapRow("SAP (KOH)", ingredient.kohSapValue) }
                if !hasProfile {
                    sheetRow(2, of: rowCount) {
                        HoneyLedgerLabeledRow("INS") {
                            if let ins = stats.ins {
                                Text.honeyLedgerFigure(ins.formatted(.number.precision(.fractionLength(1))))
                            } else {
                                notSpecifiedText
                            }
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
    private func profileTypesAndSapSections(stats: RecipeStats) -> some View {
        if Self.isPhone || !prefersColumns {
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

            sapSection(stats: stats, hasProfile: true)
        } else {
            fattyAcidColumnsSection(stats: stats)
        }
    }

    private func qualitiesSection(stats: RecipeStats) -> some View {
        Section {
            if isExpanded(.soapQualities) {
                SoapPropertiesSection(
                    stats: stats,
                    interactive: false,
                    style: .bars,
                    drawsLedgerSheet: true
                )
            }
        } header: {
            collapsibleHeader("Soap Qualities", .soapQualities)
        } footer: {
            if isExpanded(.soapQualities) {
                HoneyLedgerFooter("Outlined boxes are the usual range for a whole recipe.")
            }
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
                // The SAP figures sit under the types in the same column, as
                // two short rows that would leave a full-width sheet mostly empty.
                VStack(spacing: 24) {
                    HoneyLedgerColumn(isExpanded: isExpanded(.fattyAcidTypes)) {
                        collapsibleHeader("Fatty Acid Types", .fattyAcidTypes, animated: false)
                    } rows: {
                        FattyAcidTotalsRows(stats: stats)
                    }
                    HoneyLedgerColumn(isExpanded: isExpanded(.sapValues)) {
                        collapsibleHeader("SAP Values", .sapValues, animated: false)
                    } rows: {
                        sapRow("SAP (NaOH)", ingredient.sapValue)
                        sapRow("SAP (KOH)", ingredient.kohSapValue)
                    }
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
                notSpecifiedText
            }
        }
    }

    private var notSpecifiedText: some View {
        Text("Not specified")
            .font(.body)
            .foregroundStyle(Color.inkSoft)
    }
}
