import SwiftUI

/// How Home lays its cards out: one column, or from `ListDetailLayout`'s wide
/// width three, top-aligned.
enum HomeLayout {
    static let maximumWidth: CGFloat = 1_120
    static let spacing: CGFloat = 24
    static let wideColumnCount = 3
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
