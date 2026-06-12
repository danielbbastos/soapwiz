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
/// grows the *same* element sideways: the secondary action buttons slide out from
/// underneath the `+` (clipped to a shared capsule), while the `+` stays anchored
/// on the right as a raised circle casting a shadow over them. Falls back to acting
/// like `FloatingActionButton` when no secondary actions are supplied.
struct ExpandableFloatingActionButton: View {
    let primaryAction: () -> Void
    let secondaryActions: [FABAction]

    @State private var isExpanded = false

    private let diameter: CGFloat = 56
    private let spacing: CGFloat = 8

    private var secondaryWidth: CGFloat {
        let count = CGFloat(secondaryActions.count)
        guard count > 0 else { return 0 }
        return count * diameter + (count - 1) * spacing
    }
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
            // Shared background. The capsule's rounded right end coincides with the
            // plus circle, so the two read as one element.
            background
                .frame(width: width, height: diameter)

            // Secondary buttons, clipped to the capsule so they appear to emerge
            // from under the plus instead of sliding in from off-screen.
            secondaryGroup
                .frame(width: secondaryWidth, height: diameter)
                .offset(x: isExpanded ? -(diameter + spacing) : 0)
                .opacity(isExpanded ? 1 : 0)
                .frame(width: width, height: diameter, alignment: .trailing)
                .clipShape(.capsule)

            // The plus, raised on top, casts a shadow leftward over the buttons.
            plusButton
                .frame(width: diameter, height: diameter)
                .modifier(PlusCircle())
                .shadow(color: .black.opacity(isExpanded ? 0.22 : 0), radius: 4, x: -3, y: 1)
        }
        .frame(width: width, height: diameter, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    @ViewBuilder private var background: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(Color.accentColor)
                .shadow(radius: 4, y: 2)
        }
    }

    private var secondaryGroup: some View {
        HStack(spacing: spacing) {
            ForEach(secondaryActions) { item in
                iconButton(systemImage: item.systemImage, accessibility: item.label) {
                    collapse()
                    item.action()
                }
            }
        }
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

    private func iconButton(systemImage: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon(systemImage)
        }
        .accessibilityLabel(accessibility)
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

/// The raised circle behind the `+`: interactive glass on iOS 26, a solid accent
/// circle on earlier versions. Sits on top of the shared capsule so it can cast a
/// shadow over the revealed secondary buttons.
private struct PlusCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(Color.accentColor, in: .circle)
        }
    }
}
