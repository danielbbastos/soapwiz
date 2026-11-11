import SwiftUI

/// How Home lays its cards out: one column, or from `ListDetailLayout`'s wide
/// width three, top-aligned.
enum HomeLayout {
    static let maximumWidth: CGFloat = 1_120
    static let spacing: CGFloat = 24
    static let wideColumnCount = 3
    static let contentPadding: CGFloat = 16

    /// How far in from the screen's edge the large title starts in `width`, so it
    /// lines up with the content below it. Wide, that's the cards (or the
    /// first-run column), capped and centred inside the screen's padding; narrower,
    /// the readable column, as on other screens. Nil is the system margin, which
    /// the readable width also falls back to below 740 pt.
    static func titleMargin(width: CGFloat, isFirstRun: Bool) -> CGFloat? {
        guard ListDetailLayout.isWide(width: width) else { return ReadableWidth.margin(for: width) }
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
        if isWide {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: HomeLayout.spacing, alignment: .top),
                    count: HomeLayout.wideColumnCount
                ),
                alignment: .center,
                spacing: HomeLayout.spacing
            ) {
                content
            }
            .frame(maxWidth: HomeLayout.maximumWidth)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: HomeLayout.spacing) {
                content
            }
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
