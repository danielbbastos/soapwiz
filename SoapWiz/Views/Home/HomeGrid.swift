import SwiftUI

/// How Home lays its cards out: one column, or from `ListDetailLayout`'s wide
/// width three, top-aligned.
enum HomeLayout {
    static let maximumWidth: CGFloat = 1_120
    static let spacing: CGFloat = 24
    static let wideColumnCount = 3
    static let contentPadding: CGFloat = 16

    /// Whether Home lays out wide: three columns, the wide Insights row and the
    /// strip heatmap. Needs the width, and normal text: at accessibility sizes
    /// three columns leave each card too narrow to read.
    static func isWide(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> Bool {
        isWide(widthIsWide: ListDetailLayout.isWide(width: width), dynamicTypeSize: dynamicTypeSize)
    }

    static func isWide(widthIsWide: Bool, dynamicTypeSize: DynamicTypeSize) -> Bool {
        widthIsWide && !dynamicTypeSize.isAccessibilitySize
    }

    /// How far in from the screen's edge the large title starts in `width`, so it
    /// lines up with the content below it. Wide, that's the cards (or the
    /// first-run column), capped and centred inside the screen's padding; narrower,
    /// the readable column, as on other screens. Nil is the system margin, which
    /// the readable width also falls back to below 740 pt.
    static func titleMargin(
        width: CGFloat,
        isFirstRun: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat? {
        guard isWide(width: width, dynamicTypeSize: dynamicTypeSize) else {
            return ReadableWidth.margin(for: width)
        }
        let cap = isFirstRun ? HomeFirstRunView.maximumWidth : maximumWidth
        return contentPadding + max(0, (width - 2 * contentPadding - cap) / 2)
    }
}

struct HomeGrid<Content: View>: View {
    let isWide: Bool
    let content: Content

    init(isWide: Bool, @ViewBuilder content: () -> Content) {
        self.isWide = isWide
        self.content = content()
    }

    var body: some View {
        HomeColumnsLayout(columnCount: isWide ? HomeLayout.wideColumnCount : 1) {
            content
        }
    }
}

/// Places Home's cards row by row in `columnCount` top-aligned columns. One
/// layout for both shapes, so the cards keep their identity when the window
/// rotates and slide to their new places. Three columns are capped at
/// `HomeLayout.maximumWidth` and centred.
struct HomeColumnsLayout: Layout {
    let columnCount: Int

    static func contentWidth(width: CGFloat, columnCount: Int) -> CGFloat {
        columnCount > 1 ? min(width, HomeLayout.maximumWidth) : width
    }

    static func columnWidth(width: CGFloat, columnCount: Int) -> CGFloat {
        let count = CGFloat(max(1, columnCount))
        return (contentWidth(width: width, columnCount: columnCount) - HomeLayout.spacing * (count - 1)) / count
    }

    /// Each card's frame from its height, with the layout's origin at zero.
    /// A row is as tall as its tallest card.
    static func frames(heights: [CGFloat], width: CGFloat, columnCount: Int) -> [CGRect] {
        let count = max(1, columnCount)
        let columnWidth = columnWidth(width: width, columnCount: count)
        let originX = (width - contentWidth(width: width, columnCount: count)) / 2
        var frames: [CGRect] = []
        var originY: CGFloat = 0
        for start in stride(from: 0, to: heights.count, by: count) {
            let row = heights[start..<min(start + count, heights.count)]
            for (offset, height) in row.enumerated() {
                frames.append(CGRect(
                    x: originX + CGFloat(offset) * (columnWidth + HomeLayout.spacing),
                    y: originY,
                    width: columnWidth,
                    height: height
                ))
            }
            originY += (row.max() ?? 0) + HomeLayout.spacing
        }
        return frames
    }

    private func measuredFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columnWidth = Self.columnWidth(width: width, columnCount: columnCount)
        let heights = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        return Self.frames(heights: heights, width: width, columnCount: columnCount)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let frames = measuredFrames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = measuredFrames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

#Preview("Wide") {
    HomeGrid(isWide: true) {
        HomeCard("Curing") { Text(verbatim: "Row").padding(16) }
        HomeCard("You can make") { Text(verbatim: "Row").padding(16) }
        HomeCard("Needs attention") { Text(verbatim: "Row").padding(16) }
    }
    .padding()
}
