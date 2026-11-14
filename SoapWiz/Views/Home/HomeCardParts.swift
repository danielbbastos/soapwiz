import SwiftUI

/// The hairline between a Home card's rows.
struct HomeCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(height: 1)
    }
}

/// A card's last row when it is a link, such as "Show more".
struct HomeCardFooterButton: View {
    let title: LocalizedStringKey
    let isLast: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, isLast: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isLast = isLast
        self.action = action
    }

    var body: some View {
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
}

/// The layouts a Home card's header and rows switch between: side by side, or
/// stacked at accessibility text sizes.
enum HomeCardLayout {
    static func header(isAccessibilitySize: Bool) -> AnyLayout {
        isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    static func row(isAccessibilitySize: Bool) -> AnyLayout {
        isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}
