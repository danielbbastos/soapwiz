import SwiftUI

/// The recipe detail's stats sheets. A soap recipe gets the qualities chart and
/// its INS/iodine indicators, followed by the blend's fatty acid profile and
/// saturation totals. A non-soap recipe gets only the fatty acid composition,
/// which is the part that still means something without saponification.
///
/// Each block is one sheet row holding the shared views, as on the ingredient
/// detail, so they keep the layout they have on the recipe form's Stats tab.
/// Emits `Section`s, so it must sit directly inside a `List`.
struct RecipeDetailStatsSections: View {
    let stats: RecipeStats

    var body: some View {
        if stats.makesSoap {
            Section {
                if stats.hasOils {
                    VStack(alignment: .leading, spacing: 12) {
                        SoapPropertiesSection(stats: stats)
                    }
                    .padding(.vertical, 4)
                    .ledgerSheetRow(position: .only)
                } else {
                    inkSoftRow("Add oils to see soap properties")
                }
            } header: {
                HoneyLedgerSectionLabel("Soap properties")
            }
        }

        if stats.hasFattyAcidData {
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
        } else if stats.showsMissingFattyAcidExplanation {
            Section {
                inkSoftRow(RecipeStatsCopy.noFattyAcidData)
            } header: {
                HoneyLedgerSectionLabel("Fatty acid profile")
            }
        }
    }

    private func inkSoftRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.inkSoft)
            .ledgerSheetRow(position: .only)
    }
}
