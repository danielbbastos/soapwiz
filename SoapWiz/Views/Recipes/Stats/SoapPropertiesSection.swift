import SwiftUI

/// The soap-properties block shared by the recipe form's Stats tab and the
/// recipe detail screen: the qualities chart, the drill-down card for the
/// selected quality, and the INS / iodine indicators. Emits rows rather than a
/// `Section` so each call site keeps its own header and row background.
///
/// Every piece is a row of its own, never one row holding them all: opening
/// the card then inserts a row under a chart that stays put. Grown inside a
/// single row, the list resizes the row around content already laid out at its
/// new height, and the chart jumps while the row catches up.
struct SoapPropertiesSection: View {
    let stats: RecipeStats

    /// Whether tapping a quality bar opens the per-oil contribution card. Off on
    /// an ingredient's own detail page, where "which oil contributes this" is
    /// answered by the page itself — it's the one oil.
    var interactive: Bool = true

    /// Whether the rows draw their share of a ledger sheet, as one sheet with
    /// no rules between them. Off where the call site wraps the rows in a
    /// single row of its own, or keeps the system's grouped look.
    var drawsLedgerSheet: Bool = false

    @State private var selectedQualityName: String?

    private var selectedQuality: SoapQuality? {
        guard let name = selectedQualityName else { return nil }
        return SoapQuality.allCases.first { $0.displayName == name }
    }

    private var showsCard: Bool {
        interactive && stats.hasOils && selectedQuality != nil
    }

    private var rows: [SoapPropertiesRow] {
        var rows: [SoapPropertiesRow] = []
        if !stats.oilsMissingFattyAcidData.isEmpty { rows.append(.warning) }
        rows.append(.chart)
        if showsCard { rows.append(.card) }
        if stats.hasOils, stats.ins != nil { rows.append(contentsOf: [.ins, .iodine]) }
        return rows
    }

    var body: some View {
        IncompleteFattyAcidWarningRow(oilNames: stats.oilsMissingFattyAcidData)
            .modifier(sheetRow(.warning))

        VStack(alignment: .leading, spacing: 8) {
            Text("Shaded bands show the recommended range for each property.")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
            SoapPropertiesChartView(
                profile: stats.fattyAcidProfile,
                hasOils: stats.hasOils,
                selectedDisplayName: $selectedQualityName,
                interactive: interactive
            )
        }
        .padding(.vertical, 4)
        .modifier(sheetRow(.chart))

        if showsCard, let quality = selectedQuality {
            OilContributionCardView(
                quality: quality,
                totalValue: quality.value(from: stats.fattyAcidProfile),
                contributions: stats.contributions(for: quality),
                onClose: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedQualityName = nil
                    }
                }
            )
            .transition(.opacity)
            .modifier(sheetRow(.card))
        }

        if stats.hasOils, let ins = stats.ins {
            SoapPropertyIndicatorView(
                title: "INS",
                value: ins,
                recommended: SoapMetric.insRange,
                scale: SoapMetric.insScale,
                infoTitle: "INS",
                infoText: Self.insExplanation
            )
            .modifier(sheetRow(.ins))
            SoapPropertyIndicatorView(
                title: "Iodine",
                value: stats.iodineValue,
                recommended: SoapMetric.iodineRange,
                scale: SoapMetric.iodineScale,
                infoTitle: "Iodine value",
                infoText: Self.iodineExplanation
            )
            .modifier(sheetRow(.iodine))
        }
    }

    private func sheetRow(_ row: SoapPropertiesRow) -> SoapPropertiesSheetRow {
        let rows = rows
        let position = LedgerSheetPosition.position(index: rows.firstIndex(of: row) ?? 0, count: rows.count)
        return SoapPropertiesSheetRow(position: drawsLedgerSheet ? position : nil)
    }

    private static let insExplanation =
        "INS estimates a bar's overall hardness from the blend's saponification and iodine values. "
        + "136–170 is the usual target: lower blends tend to be soft, higher ones brittle. "
        + "Treat it as a rough guide — the individual properties tell you more."

    private static let iodineExplanation =
        "The iodine value measures how unsaturated the oils are. Higher values mean softer bars "
        + "that are more prone to rancidity (DOS); lower values mean harder, longer-lasting bars. "
        + "41–70 is the usual target."
}

private enum SoapPropertiesRow {
    case warning, chart, card, ins, iodine
}

/// A row's share of the ledger sheet with no rule under it, or nothing at all
/// when there is no position.
private struct SoapPropertiesSheetRow: ViewModifier {
    let position: LedgerSheetPosition?

    func body(content: Content) -> some View {
        if let position {
            content
                .ledgerSheetRow(position: position)
                .listRowSeparator(.hidden)
        } else {
            content
        }
    }
}
