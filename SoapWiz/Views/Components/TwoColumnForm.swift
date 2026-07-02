import SwiftUI

/// Which detail layout a horizontal size class gets: one stacked form in
/// compact, two side-by-side columns in regular (iPad, even in portrait).
enum DetailLayout {
    case single
    case twoColumn

    init(sizeClass: UserInterfaceSizeClass?) {
        self = sizeClass == .regular ? .twoColumn : .single
    }
}

/// Compact: a single `Form` containing the leading then trailing sections —
/// identical to the pre-iPad stacked layout.
/// Regular: two side-by-side `Form`s, each scrolling independently.
struct TwoColumnForm<Leading: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let twoColumnsAllowed: Bool
    private let leading: Leading
    private let trailing: Trailing

    /// `twoColumnsAllowed` lets the owner veto the side-by-side layout when
    /// the detail column is squeezed (e.g. while the sidebar is open), which
    /// the size class alone can't express.
    init(
        twoColumnsAllowed: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.twoColumnsAllowed = twoColumnsAllowed
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        switch DetailLayout(sizeClass: twoColumnsAllowed ? horizontalSizeClass : .compact) {
        case .twoColumn:
            HStack(alignment: .top, spacing: 0) {
                Form { leading }
                    .warmBackground()
                Form { trailing }
                    .warmBackground()
            }
            .background(Color.warmBackground.ignoresSafeArea())
        case .single:
            Form {
                leading
                trailing
            }
            .warmBackground()
        }
    }
}
