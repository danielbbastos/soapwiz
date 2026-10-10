import SwiftUI
import UIKit

/// The recipe detail's stats sheets. A soap recipe gets the qualities chart and
/// its INS/iodine indicators, followed by the blend's fatty acid profile and
/// saturation totals. A non-soap recipe gets only the fatty acid composition,
/// which is the part that still means something without saponification.
///
/// The soap properties are rows of a sheet (see `SoapPropertiesSection`); the
/// fatty acid blocks are each one sheet row holding the shared views, as on the
/// ingredient detail. Emits `Section`s, so it must sit directly inside a `List`.
struct RecipeDetailStatsSections: View {
    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    let stats: RecipeStats

    var body: some View {
        if stats.makesSoap {
            Section {
                if stats.hasOils {
                    SoapPropertiesSection(stats: stats, drawsLedgerSheet: true)
                } else {
                    inkSoftRow("Add oils to see soap properties")
                }
            } header: {
                HoneyLedgerSectionLabel("Soap properties")
            }
        }

        if stats.hasFattyAcidData {
            if Self.isPhone {
                stackedFattyAcidSections
            } else {
                fattyAcidColumnsSection
            }
        } else if stats.showsMissingFattyAcidExplanation {
            Section {
                inkSoftRow(RecipeStatsCopy.noFattyAcidData)
            } header: {
                HoneyLedgerSectionLabel("Fatty acid profile")
            }
        }
    }

    @ViewBuilder
    private var stackedFattyAcidSections: some View {
        Section {
            VStack(spacing: 10) { FattyAcidBreakdownRows(stats: stats) }
                .padding(.vertical, 4)
                .ledgerSheetRow(position: .only)
        } header: {
            HoneyLedgerSectionLabel("Fatty acid profile")
        }
        Section {
            VStack(spacing: 10) { FattyAcidTotalsRows(stats: stats, showsIodine: !stats.makesSoap) }
                .padding(.vertical, 4)
                .ledgerSheetRow(position: .only)
        } header: {
            HoneyLedgerSectionLabel(RecipeStatsCopy.totalsHeader)
        }
    }

    /// The profile and the totals side by side on iPad: their labels never
    /// change and are short.
    private var fattyAcidColumnsSection: some View {
        Section {
            HoneyLedgerColumns {
                HoneyLedgerColumn {
                    HoneyLedgerSectionLabel("Fatty acid profile")
                } rows: {
                    FattyAcidBreakdownRows(stats: stats)
                }
            } trailing: {
                HoneyLedgerColumn {
                    HoneyLedgerSectionLabel(RecipeStatsCopy.totalsHeader)
                } rows: {
                    FattyAcidTotalsRows(stats: stats, showsIodine: !stats.makesSoap)
                }
            }
        }
    }

    private func inkSoftRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.inkSoft)
            .ledgerSheetRow(position: .only)
    }
}
