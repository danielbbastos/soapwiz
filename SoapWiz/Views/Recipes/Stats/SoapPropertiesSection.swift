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

    /// Bars draw each quality as a compact one-line row with no status tag, since
    /// one oil is not expected to land inside a whole recipe's usual ranges.
    var style: SoapPropertiesStyle = .chart

    /// Whether the rows draw their share of a ledger sheet, as one sheet with
    /// no rules between them. Off where the call site wraps the rows in a
    /// single row of its own, or keeps the system's grouped look.
    var drawsLedgerSheet: Bool = false

    @Environment(\.displayScale) private var displayScale

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
        switch style {
        case .chart:
            rows.append(.chart)
        case .bars:
            rows.append(contentsOf: SoapQuality.allCases.map(SoapPropertiesRow.quality))
        }
        if showsCard { rows.append(.card) }
        if stats.hasOils, stats.ins != nil { rows.append(contentsOf: [.ins, .iodine]) }
        return rows
    }

    var body: some View {
        IncompleteFattyAcidWarningRow(oilNames: stats.oilsMissingFattyAcidData)
            .modifier(sheetRow(.warning))

        switch style {
        case .chart:
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
        case .bars:
            ForEach(SoapQuality.allCases) { quality in
                metricView(
                    for: .quality(quality),
                    title: quality.displayName,
                    value: quality.value(from: stats.fattyAcidProfile),
                    range: quality.recommendedRange,
                    scale: 0...100,
                    infoTitle: quality.displayName,
                    infoText: quality.explanation
                )
                .modifier(sheetRow(.quality(quality), isCompact: true))
            }
        }

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
            VStack(alignment: .leading, spacing: 13) {
                // Drawn in the row rather than as the list's separator, which
                // the ledger sheet hides row by row. The rows around it add
                // their own space (the list inset, or `rowVerticalPadding`
                // where that inset is zeroed), so 13pt more sets INS and
                // Iodine apart from the qualities as a group. Its frame is a
                // whole point so the row's height stays on a pixel boundary,
                // where a fractional edge shows as a seam.
                if style == .bars {
                    Rectangle()
                        .fill(Color.rule)
                        .frame(height: 1 / displayScale)
                        .frame(height: 1, alignment: .top)
                        .padding(.top, 13)
                }
                metricView(for: .ins, title: "INS", value: ins, range: SoapMetric.insRange,
                           scale: SoapMetric.insScale, infoTitle: "INS", infoText: Self.insExplanation)
            }
            .modifier(sheetRow(.ins, isCompact: style == .bars))
            metricView(for: .iodine, title: "Iodine", value: stats.iodineValue, range: SoapMetric.iodineRange,
                       scale: SoapMetric.iodineScale, infoTitle: "Iodine value", infoText: Self.iodineExplanation)
                .modifier(sheetRow(.iodine, isCompact: style == .bars))
        }
    }

    @ViewBuilder
    private func metricView(
        for row: SoapPropertiesRow,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        scale: ClosedRange<Double>,
        infoTitle: String,
        infoText: String
    ) -> some View {
        switch style {
        case .chart:
            SoapPropertyIndicatorView(
                title: title,
                value: value,
                recommended: range,
                scale: scale,
                infoTitle: infoTitle,
                infoText: infoText
            )
        case .bars:
            SoapPropertyRowView(
                title: title,
                value: value,
                recommended: range,
                scale: scale,
                infoTitle: infoTitle,
                infoText: infoText,
                minHeight: drawsLedgerSheet ? CompactRowInsets.rowMinHeight : 44,
                verticalPadding: drawsLedgerSheet ? CompactRowInsets.rowVerticalPadding : 0,
                paddedEdges: position(of: row).innerEdges
            )
        }
    }

    private func position(of row: SoapPropertiesRow) -> LedgerSheetPosition {
        let rows = rows
        return LedgerSheetPosition.position(index: rows.firstIndex(of: row) ?? 0, count: rows.count)
    }

    private func sheetRow(_ row: SoapPropertiesRow, isCompact: Bool = false) -> SoapPropertiesSheetRow {
        SoapPropertiesSheetRow(
            position: drawsLedgerSheet ? position(of: row) : nil,
            isCompact: isCompact,
            outerPadding: style == .bars ? 4 : 0
        )
    }

    private static let insExplanation =
        "INS estimates a bar's overall hardness from the blend's saponification and iodine values. "
        + "136 to 170 is the usual target: lower blends tend to be soft, higher ones brittle. "
        + "Treat it as a rough guide. The individual properties tell you more."

    private static let iodineExplanation =
        "The iodine value measures how unsaturated the oils are. Higher values mean softer bars "
        + "that are more prone to rancidity (DOS); lower values mean harder, longer-lasting bars. "
        + "41 to 70 is the usual target."
}

/// How `SoapPropertiesSection` draws the six qualities: the vertical chart a
/// recipe uses, or one compact row per quality for a single oil.
enum SoapPropertiesStyle {
    case chart
    case bars
}

private enum SoapPropertiesRow: Equatable {
    case warning, chart, quality(SoapQuality), card, ins, iodine
}

private extension LedgerSheetPosition {
    /// The edges facing another row of the sheet.
    var innerEdges: Edge.Set {
        var edges: Edge.Set = []
        if !roundsTop { edges.insert(.top) }
        if !roundsBottom { edges.insert(.bottom) }
        return edges
    }

    /// The edges that are the sheet's own top or bottom.
    var outerEdges: Edge.Set {
        var edges: Edge.Set = []
        if roundsTop { edges.insert(.top) }
        if roundsBottom { edges.insert(.bottom) }
        return edges
    }
}

/// Zeroes a list row's vertical inset from iOS 26 on the edges facing another
/// row, where the row's own minimum height then sets the pitch. The sheet's
/// outer edges keep the system inset. Before iOS 26 there is no per-axis form
/// and the system's side insets can't be read, so the default insets stay,
/// which keeps the rows aligned with the rest of the sheet, and the row's own
/// minimum drops to nothing: the inset and the content already make a row
/// about 44pt.
private struct CompactRowInsets: ViewModifier {
    let isCompact: Bool
    let position: LedgerSheetPosition

    static var rowMinHeight: CGFloat {
        if #available(iOS 26, *) { 44 } else { 0 }
    }

    /// What a two-line row adds itself where the inset is zeroed, so one quality
    /// sits about 14pt from the next.
    static var rowVerticalPadding: CGFloat {
        if #available(iOS 26, *) { 7 } else { 0 }
    }

    func body(content: Content) -> some View {
        if isCompact, #available(iOS 26, *) {
            content.listRowInsets(position.innerEdges, 0)
        } else {
            content
        }
    }
}

/// A row's share of the ledger sheet with no rule under it, or nothing at all
/// when there is no position.
private struct SoapPropertiesSheetRow: ViewModifier {
    let position: LedgerSheetPosition?

    /// Drops the list's own vertical inset, for rows that carry their 44pt
    /// height themselves and would otherwise sit about 74pt apart.
    var isCompact = false

    /// Extra space on the sheet's own top and bottom edges, as the other
    /// sheets' rows add beyond the list inset.
    var outerPadding: CGFloat = 0

    func body(content: Content) -> some View {
        if let position {
            content
                .padding(position.outerEdges, outerPadding)
                .ledgerSheetRow(position: position)
                .modifier(CompactRowInsets(isCompact: isCompact, position: position))
                .listRowSeparator(.hidden)
        } else {
            content
        }
    }
}
