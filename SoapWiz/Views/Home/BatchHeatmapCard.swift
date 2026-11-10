import SwiftData
import SwiftUI

/// Insights' batch heatmap: one square per week of the past year, darker the
/// more batches were made. On a phone the weeks sit in month columns; on a
/// wide screen they run as two strips of 26.
struct BatchHeatmapCard: View {
    @Environment(BatchRows.self) private var batchRows
    @Environment(\.homeNow) private var now
    @State private var selectedID: Date?

    let isWide: Bool

    private var heatmap: BatchHeatmap {
        BatchHeatmap(batches: batchRows.batches, now: now)
    }

    var body: some View {
        let heatmap = heatmap
        let selected = heatmap.weeks.first { $0.id == selectedID }
        VStack(alignment: .leading, spacing: 12) {
            header(heatmap)
            if isWide {
                BatchHeatmapStrip(heatmap: heatmap, selectedID: $selectedID)
            } else {
                BatchHeatmapMonthGrid(heatmap: heatmap, selectedID: $selectedID)
            }
            detail(heatmap, selected: selected)
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerSheet()
        .onChange(of: heatmap.weeks.first?.id) { _, _ in
            selectedID = nil
        }
    }

    private func header(_ heatmap: BatchHeatmap) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: 8)
                total(heatmap)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                total(heatmap)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: some View {
        Text("Past year")
            .font(.title3.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(Color.ink)
    }

    private func total(_ heatmap: BatchHeatmap) -> some View {
        Text("^[\(heatmap.total) batch](inflect: true)")
            .font(.body.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
    }

    private func detail(_ heatmap: BatchHeatmap, selected: HeatmapWeek?) -> some View {
        Group {
            if let selected {
                let range = Text(heatmap.rangeText(for: selected))
                let count = Text("^[\(selected.count) batch](inflect: true)")
                    .monospacedDigit()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        range
                        Spacer(minLength: 8)
                        count
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        range
                        count
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink)
            } else {
                Text("Tap a week to see its batches")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.honey, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        let caption = isWide ? "Each square is a week, oldest first." : "Each square is a week."
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(caption))
                Spacer(minLength: 8)
                swatches
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(caption))
                HStack(spacing: 6) { swatches }
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.inkSoft)
    }

    @ViewBuilder
    private var swatches: some View {
        Text("None")
        ForEach(0..<4, id: \.self) { level in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.heatmapLevel(level))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
        Text("3+")
    }
}

/// One week's square.
private struct HeatmapCell: View {
    let week: HeatmapWeek
    let heatmap: BatchHeatmap
    let height: CGFloat
    @Binding var selectedID: Date?

    private var isSelected: Bool { week.id == selectedID }

    var body: some View {
        Button {
            selectedID = isSelected ? nil : week.id
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.heatmapLevel(BatchHeatmap.level(for: week.count)))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.heatmapRing, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(heatmap.rangeText(for: week)), ^[\(week.count) batch](inflect: true)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BatchHeatmapMonthGrid: View {
    let heatmap: BatchHeatmap
    @Binding var selectedID: Date?
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 18

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .frame(width: 0, height: 0)
                ForEach(heatmap.months) { month in
                    Text(month.initial)
                        .font(.caption2)
                        .foregroundStyle(Color.inkSoft)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(0..<heatmap.rowCount, id: \.self) { row in
                GridRow {
                    Text("W\(row + 1)")
                        .font(.caption2)
                        .foregroundStyle(Color.inkSoft)
                        .accessibilityHidden(true)
                    ForEach(heatmap.months) { month in
                        if let week = month.weeks.first(where: { $0.row == row }) {
                            HeatmapCell(week: week, heatmap: heatmap, height: cellHeight, selectedID: $selectedID)
                        } else {
                            Color.clear
                                .frame(height: cellHeight)
                        }
                    }
                }
            }
        }
    }
}

private struct BatchHeatmapStrip: View {
    let heatmap: BatchHeatmap
    @Binding var selectedID: Date?

    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(Array(heatmap.strip.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { week in
                        HeatmapCell(week: week, heatmap: heatmap, height: 22, selectedID: $selectedID)
                    }
                }
            }
        }
    }
}

#if DEBUG
@MainActor
struct BatchHeatmapPreviewData {
    let container: ModelContainer
    let batchRows: BatchRows
    let navigation = AppNavigation()

    init(batchCount: Int = 60) {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("The preview container couldn't be made.")
        }
        let context = container.mainContext
        let calendar = Calendar.current
        for index in 0..<batchCount {
            let daysAgo = (index * 37) % 360
            let created = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            context.insert(Batch(
                recipe: nil,
                code: "SPB-\(index)",
                recipeName: "Simple Palm Bar",
                dateCreated: created,
                batchCount: 1,
                cureDays: 42
            ))
        }
        try? context.save()
        self.container = container
        batchRows = BatchRows(context: context)
    }
}

#Preview("Heatmap, phone") {
    let data = BatchHeatmapPreviewData()
    BatchHeatmapCard(isWide: false)
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}

#Preview("Heatmap, iPad", traits: .fixedLayout(width: 760, height: 320)) {
    let data = BatchHeatmapPreviewData()
    BatchHeatmapCard(isWide: true)
        .padding(16)
        .ledgerBackground()
        .environment(data.batchRows)
        .environment(data.navigation)
        .modelContainer(data.container)
}
#endif
