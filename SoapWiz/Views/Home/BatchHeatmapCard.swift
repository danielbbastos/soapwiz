import SwiftData
import SwiftUI

/// Insights' batch heatmap: one square per week of the past year, darker the
/// more batches were made. On a phone the weeks sit in month columns; on a
/// wide screen they run as two strips of 26.
struct BatchHeatmapCard: View {
    @Environment(BatchRows.self) private var batchRows
    @Environment(\.homeNow) private var now

    let isWide: Bool

    var body: some View {
        BatchHeatmapContent(heatmap: BatchHeatmap(batches: batchRows.batches, now: now), isWide: isWide)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ledgerSheet()
    }
}

/// The card's content. It owns the selection, so a tap redraws only this and
/// reads the heatmap already built.
private struct BatchHeatmapContent: View {
    @State private var selectedID: Date?

    let heatmap: BatchHeatmap
    let isWide: Bool

    var body: some View {
        let selected = heatmap.weeks.first { $0.id == selectedID }
        VStack(alignment: .leading, spacing: 12) {
            header
            if isWide {
                BatchHeatmapStrip(heatmap: heatmap, selectedID: $selectedID)
            } else {
                BatchHeatmapMonthGrid(heatmap: heatmap, selectedID: $selectedID)
            }
            detail(selected: selected)
            legend
        }
        .onChange(of: heatmap.weeks.first?.id) { _, _ in
            selectedID = nil
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: 8)
                total
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                total
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

    private var total: some View {
        Text("^[\(heatmap.total) batch](inflect: true)")
            .font(.body.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
    }

    private func detail(selected: HeatmapWeek?) -> some View {
        Group {
            if let selected {
                let range = Text(selected.rangeText)
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
        .accessibilityLabel(Text("\(week.rangeText), ^[\(week.count) batch](inflect: true)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BatchHeatmapMonthGrid: View {
    let heatmap: BatchHeatmap
    @Binding var selectedID: Date?
    @ScaledMetric(relativeTo: .caption) private var minimumCellHeight: CGFloat = 18
    @State private var gridWidth: CGFloat = 0

    private static let spacing: CGFloat = 4
    private static let markerWidth: CGFloat = 24

    /// Cells keep their height on a phone, where they are near square, and grow
    /// with their width on a wide card so they never stretch past
    /// `HeatmapCellShape.maximumAspectRatio`.
    private var cellHeight: CGFloat {
        let columns = CGFloat(max(heatmap.months.count, 1))
        let cellWidth = (gridWidth - Self.markerWidth - Self.spacing * columns) / columns
        return HeatmapCellShape.height(forWidth: cellWidth, minimum: minimumCellHeight)
    }

    var body: some View {
        grid
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private var grid: some View {
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
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
                            HeatmapCell(week: week, height: cellHeight, selectedID: $selectedID)
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
            ForEach(Array(heatmap.strip.enumerated()), id: \.offset) { index, row in
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .frame(width: 0, height: 0)
                    ForEach(Array(row.enumerated()), id: \.offset) { column, _ in
                        Text(heatmap.stripMonthLabels[index][column] ?? "")
                            .font(.caption2)
                            .foregroundStyle(Color.inkSoft)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, index > 0 ? 6 : 0)
                GridRow {
                    Text(heatmap.stripMarkers[index])
                        .font(.caption2)
                        .foregroundStyle(Color.inkSoft)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(true)
                    ForEach(row) { week in
                        HeatmapCell(week: week, height: 22, selectedID: $selectedID)
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

    private struct Sample {
        let name: String
        let cost: Double
        let weightInGrams: Double
    }

    private static let recipes = [
        Sample(name: "Simple Palm Bar", cost: 9.5, weightInGrams: 1_000),
        Sample(name: "Lavender Oat Bar", cost: 14.2, weightInGrams: 1_100),
        Sample(name: "Castile Olive Bar", cost: 21.8, weightInGrams: 1_200),
        Sample(name: "Shea Butter Bar", cost: 17.4, weightInGrams: 1_000),
        Sample(name: "Coconut Salt Bar", cost: 11.1, weightInGrams: 1_300),
        Sample(name: "Honey Goat Milk Bar", cost: 19.9, weightInGrams: 900)
    ]

    init(batchCount: Int = 60, weighted: Bool = true) {
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
            let recipe = Self.recipes[index % Self.recipes.count]
            context.insert(Batch(
                recipe: nil,
                code: "SPB-\(index)",
                recipeName: recipe.name,
                dateCreated: created,
                batchCount: 1,
                totalCost: weighted ? recipe.cost : 0,
                totalWeight: weighted ? recipe.weightInGrams : 0,
                totalWeightUnit: weighted ? "g" : "",
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
