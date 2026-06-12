import SwiftUI

/// A secondary action revealed when an `ExpandableFloatingActionButton` is expanded.
struct FABAction: Identifiable {
    /// Stable across parent re-renders so `ForEach` doesn't spuriously re-run the
    /// reveal transition. Labels are unique within a single FAB's action set.
    var id: String { label }
    let label: String
    let systemImage: String
    let action: () -> Void
}

/// A floating `+` button that tapping performs the primary action. Long-pressing
/// grows the *same* element sideways: the secondary action buttons (icon + label)
/// slide out from underneath the `+` (clipped to a shared capsule), while the `+`
/// stays anchored on the right as a raised circle. Falls back to acting like
/// `FloatingActionButton` when no secondary actions are supplied.
struct ExpandableFloatingActionButton: View {
    let primaryAction: () -> Void
    let secondaryActions: [FABAction]

    @State private var isExpanded = false
    /// Natural width of the labelled secondary buttons, measured so the capsule can
    /// size to whatever the labels need.
    @State private var secondaryContentWidth: CGFloat = 0

    private let diameter: CGFloat = 56
    private let spacing: CGFloat = 8

    private var secondaryWidth: CGFloat { max(secondaryContentWidth, diameter) }
    private var expandedWidth: CGFloat { diameter + spacing + secondaryWidth }
    private var width: CGFloat { isExpanded ? expandedWidth : diameter }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Button(action: collapse) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            control
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
    }

    private var control: some View {
        ZStack(alignment: .trailing) {
            // Shared background, with the element's drop shadow over the list below.
            background
                .frame(width: width, height: diameter)
                .shadow(color: .black.opacity(isExpanded ? 0.22 : 0.12),
                        radius: isExpanded ? 10 : 4,
                        y: isExpanded ? 5 : 2)

            // Secondary buttons, clipped to the capsule so they appear to emerge
            // from under the plus instead of sliding in from off-screen.
            secondaryGroup
                .offset(x: isExpanded ? -(diameter + spacing) : 0)
                .opacity(isExpanded ? 1 : 0)
                .frame(width: width, height: diameter, alignment: .trailing)
                .clipShape(.capsule)

            // The plus, raised on top when expanded, casting a soft shadow over the
            // buttons. Collapsed, it is simply the icon sitting on the background.
            plusButton
                .frame(width: diameter, height: diameter)
                .modifier(RaisedPlus(raised: isExpanded))
                .shadow(color: .black.opacity(isExpanded ? 0.10 : 0), radius: 3, x: -2, y: 1)
        }
        .frame(width: width, height: diameter, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onPreferenceChange(FABWidthKey.self) { secondaryContentWidth = $0 }
    }

    @ViewBuilder private var background: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule().fill(Color.accentColor)
        }
    }

    private var secondaryGroup: some View {
        HStack(spacing: spacing) {
            ForEach(secondaryActions) { item in
                secondaryButton(item)
            }
        }
        .fixedSize()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FABWidthKey.self, value: proxy.size.width)
            }
        )
    }

    private func secondaryButton(_ item: FABAction) -> some View {
        Button {
            collapse()
            item.action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.title3.weight(.semibold))
                Text(item.label)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(iconColor)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .frame(height: diameter)
        }
        .accessibilityLabel(item.label)
    }

    private var plusButton: some View {
        // A long press must expand without also firing the tap on release, so the
        // two gestures are exclusive: the long press wins when held, the tap fires
        // only when it doesn't. A plain `Button` would run both.
        icon("plus")
            .contentShape(.circle)
            .gesture(
                ExclusiveGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        guard !secondaryActions.isEmpty else { return }
                        expand()
                    },
                    TapGesture().onEnded {
                        primaryAction()
                        if isExpanded { collapse() }
                    }
                )
            )
            .accessibilityElement()
            .accessibilityLabel("Add")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(secondaryActions.isEmpty ? "" : "Long press for more actions")
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(iconColor)
            .frame(width: diameter, height: diameter)
    }

    private var iconColor: Color {
        if #available(iOS 26, *) { Color.warmInk } else { .white }
    }

    private func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }
}

/// Measures the natural width of the labelled secondary buttons.
private struct FABWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The raised circle behind the `+` while expanded: interactive glass on iOS 26,
/// a solid accent circle on earlier versions. Collapsed, the `+` needs no circle of
/// its own — it sits directly on the shared background.
private struct RaisedPlus: ViewModifier {
    let raised: Bool

    func body(content: Content) -> some View {
        if raised {
            if #available(iOS 26, *) {
                content.glassEffect(.regular.interactive(), in: .circle)
            } else {
                content.background(Color.accentColor, in: .circle)
            }
        } else {
            content
        }
    }
}
