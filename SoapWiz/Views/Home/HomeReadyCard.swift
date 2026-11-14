import SwiftData
import SwiftUI

/// Home's Ready to use card: batches that finished curing within the last 30
/// days and that the user hasn't marked seen (by opening one, "Got it" or
/// "Clear all"), most recently ready first. Absent when there are none.
struct HomeReadyCard: View {
    @Environment(BatchRows.self) private var batchRows
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.homeNow) private var now
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = false

    private var ready: HomeReady {
        HomeReady(batches: batchRows.batches, now: now)
    }

    var body: some View {
        let ready = ready
        if ready.count > 0 {
            HomeCard("Ready to use") {
                header(ready)
                let visible = ready.visibleItems(isExpanded: isExpanded)
                let historyCount = ready.historyCount(isExpanded: isExpanded)
                ForEach(Array(visible.enumerated()), id: \.element.batch.id) { index, item in
                    HomeCardDivider()
                    row(item, isLast: !ready.canExpand && index == visible.count - 1)
                }
                if ready.canExpand {
                    HomeCardDivider()
                    HomeCardFooterButton(
                        isExpanded ? "Show less" : "Show more",
                        isLast: historyCount == 0
                    ) {
                        withAnimation { isExpanded.toggle() }
                    }
                }
                if historyCount > 0 {
                    HomeCardDivider()
                    HomeCardFooterButton("\(historyCount) more in History", isLast: true) {
                        navigation.selectedTab = .history
                    }
                }
            }
        }
    }

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    private var headerLayout: AnyLayout { HomeCardLayout.header(isAccessibilitySize: isAccessibilitySize) }

    private var rowLayout: AnyLayout { HomeCardLayout.row(isAccessibilitySize: isAccessibilitySize) }

    private func header(_ ready: HomeReady) -> some View {
        headerLayout {
            Text("^[\(ready.count) batch](inflect: true) ready")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            if !isAccessibilitySize {
                Spacer(minLength: 8)
            }
            if ready.count >= 2 {
                Button("Clear all") {
                    markSeen(ready.items.map(\.batch))
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .accessibilityLabel("Mark all \(ready.count) ready batches as seen")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func markSeen(_ batches: [Batch]) {
        withAnimation { HomeReady.markSeen(batches, context: modelContext) }
    }

    private func row(_ item: HomeReadyItem, isLast: Bool) -> some View {
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            rowButton(item, isLast: isLast)
            gotItButton(item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Mark as seen", systemImage: "checkmark.circle") {
                markSeen([item.batch])
            }
        }
    }

    private func gotItButton(_ item: HomeReadyItem) -> some View {
        Button {
            markSeen([item.batch])
        } label: {
            Text("Got it")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.trailing, isAccessibilitySize ? 0 : 4)
        .padding(.leading, isAccessibilitySize ? 4 : 0)
        .padding(.bottom, isAccessibilitySize ? 6 : 0)
        .accessibilityLabel("Mark \(item.batch.recipeName) as seen")
    }

    private func rowButton(_ item: HomeReadyItem, isLast: Bool) -> some View {
        Button {
            navigation.pushOnHome(item.batch)
        } label: {
            rowLayout {
                if !isAccessibilitySize {
                    ReadyMark()
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
        }
        .buttonStyle(HomeRowButtonStyle(isLast: isLast))
        .accessibilityElement(children: .combine)
    }
}

/// A full ring with a check, the size of the Curing card's progress ring.
/// Decorative: the "Ready" stamp beside it says the same.
private struct ReadyMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.success, lineWidth: 4)
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.success)
        }
        .padding(2)
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

#if DEBUG
@MainActor
private struct HomeReadyCardPreviewData {
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
            ("Oat Milk Bar", "OMB-261001-01", 42, 43),
            ("Simple Palm Bar", "SPB-261001-01", 28, 29),
            ("Castile Olive Bar", "COB-260901-01", 60, 65)
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
        HomeReadyCard()
            .padding(16)
            .ledgerBackground()
            .environment(batchRows)
            .environment(navigation)
            .modelContainer(container)
    }
}

#Preview("Ready card") {
    HomeReadyCardPreviewData().card()
}
#endif
