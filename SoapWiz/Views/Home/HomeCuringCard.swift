import SwiftData
import SwiftUI

/// Home's Curing card: every batch still curing, soonest ready first, under
/// the ones that finished in the last few days. Absent when there are none.
struct HomeCuringCard: View {
    @Environment(BatchRows.self) private var batchRows
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.homeNow) private var now
    @State private var isExpanded = false

    private var curing: HomeCuring {
        HomeCuring(batches: batchRows.batches, now: now)
    }

    var body: some View {
        let curing = curing
        if curing.count > 0 {
            HomeCard("Curing", tourAnchor: .homeCuring) {
                header(curing)
                let visible = curing.visibleItems(isExpanded: isExpanded)
                let historyCount = curing.historyCount(isExpanded: isExpanded)
                ForEach(Array(visible.enumerated()), id: \.element.batch.id) { index, item in
                    divider
                    row(item, isLast: !curing.canExpand && index == visible.count - 1)
                }
                if curing.canExpand {
                    divider
                    footerButton(
                        isExpanded ? "Show less" : "Show more",
                        isLast: historyCount == 0
                    ) {
                        withAnimation { isExpanded.toggle() }
                    }
                }
                if historyCount > 0 {
                    divider
                    footerButton("\(historyCount) more in History", isLast: true) {
                        navigation.selectedTab = .history
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(height: 1)
    }

    private func footerButton(
        _ title: LocalizedStringKey,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowButtonStyle(isLast: isLast))
    }

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    private var headerLayout: AnyLayout {
        isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    private var rowLayout: AnyLayout {
        isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func header(_ curing: HomeCuring) -> some View {
        headerLayout {
            headerTitle(curing)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.ink)
            if !isAccessibilitySize {
                Spacer(minLength: 8)
            }
            if curing.readyThisWeekCount > 0 {
                Text("\(curing.readyThisWeekCount) ready this week")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func headerTitle(_ curing: HomeCuring) -> Text {
        if curing.readyCount == 0 {
            Text("^[\(curing.curingCount) batch](inflect: true) curing")
        } else if curing.curingCount == 0 {
            Text("\(curing.readyCount) ready")
        } else {
            Text("\(curing.curingCount) curing · \(curing.readyCount) ready")
        }
    }

    private func row(_ item: HomeCuringItem, isLast: Bool) -> some View {
        Button {
            navigation.pushOnHome(item.batch)
        } label: {
            rowLayout {
                if !isAccessibilitySize {
                    CureProgressRing(progress: item.progress, isComplete: item.isReady)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.batch.recipeName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text(item.batch.code)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.inkSoft)
                }
                if !isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                VStack(alignment: isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                    if let remaining = item.remaining {
                        CureLengthText.remainingShort(remaining)
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                            .accessibilityLabel(CureLengthText.remaining(remaining))
                        Text("Ready \(item.readyDate.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                    } else {
                        StatusStamp(
                            word: String(localized: "Ready"),
                            tone: .success,
                            glyph: "checkmark.circle",
                            isInked: true
                        )
                        .fixedSize()
                        .padding(.vertical, 3)
                        Text(item.readyDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
        }
        .buttonStyle(HomeRowButtonStyle(isHighlighted: item.isReadyThisWeek, isLast: isLast))
        .accessibilityElement(children: .combine)
    }
}

/// A track and an arc that fills as the cure goes. Decorative: the time left
/// beside it says the same.
private struct CureProgressRing: View {
    let progress: Double
    var isComplete = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.chartBand, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(isComplete ? Color.success : Color.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

#if DEBUG
@MainActor
private struct HomeCuringCardPreviewData {
    let container: ModelContainer
    let batchRows: BatchRows
    let navigation = AppNavigation()

    init() {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("The preview container couldn't be made.")
        }
        let context = container.mainContext
        let calendar = Calendar.current
        let samples = [
            ("Simple Palm Bar", "SPB-261015-01", 42, 39),
            ("Lavender Oat Bar", "LOB-261020-01", 42, 21),
            ("Castile Olive Bar", "COB-261108-01", 60, 0),
            ("Oat Milk Bar", "OMB-261001-01", 28, 30)
        ]
        for (name, code, cureDays, daysAgo) in samples {
            let created = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            context.insert(Batch(
                recipe: nil,
                code: code,
                recipeName: name,
                dateCreated: created,
                batchCount: 1,
                cureDays: cureDays
            ))
        }
        try? context.save()
        self.container = container
        batchRows = BatchRows(context: context)
    }

    func card() -> some View {
        HomeCuringCard()
            .padding(16)
            .ledgerBackground()
            .environment(batchRows)
            .environment(navigation)
            .modelContainer(container)
    }
}

#Preview("Curing card") {
    HomeCuringCardPreviewData().card()
}
#endif
