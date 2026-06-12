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
/// grows the *same* element sideways into a single capsule: the secondary action
/// buttons slide out from underneath the `+`, which stays anchored on the right and
/// casts a slight shadow over them. Falls back to acting like `FloatingActionButton`
/// when no secondary actions are supplied.
struct ExpandableFloatingActionButton: View {
    let primaryAction: () -> Void
    let secondaryActions: [FABAction]

    @State private var isExpanded = false

    private let diameter: CGFloat = 56

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

    /// A single capsule that widens to the left as the secondary buttons appear.
    /// Because the control is anchored bottom-trailing, growing the `HStack` keeps
    /// the `+` fixed on the right while the leading edge extends outward.
    private var control: some View {
        HStack(spacing: 4) {
            secondaryButtons
            plusButton
        }
        .padding(.horizontal, isExpanded ? 6 : 0)
        .modifier(UnifiedCapsule(iconColor: iconColor))
    }

    @ViewBuilder private var secondaryButtons: some View {
        if isExpanded {
            ForEach(secondaryActions) { item in
                iconButton(systemImage: item.systemImage, accessibility: item.label) {
                    collapse()
                    item.action()
                }
                // Sits a touch lower than the `+` so the `+` reads as raised over it,
                // and slides out from under the `+` rather than fading in place.
                .offset(y: 3)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var plusButton: some View {
        // A long press must expand without also firing the tap on release, so the
        // two gestures are exclusive: the long press wins when held, the tap fires
        // only when it doesn't. A plain `Button` would run both.
        icon("plus")
            .shadow(color: .black.opacity(isExpanded ? 0.18 : 0), radius: 3, x: -2, y: 2)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            isExpanded = false
        }
    }
}

/// The single background uniting the buttons: one interactive glass capsule on
/// iOS 26, a solid accent capsule on earlier versions. A capsule collapses to a
/// circle when it only contains the `+`.
private struct UnifiedCapsule: ViewModifier {
    let iconColor: Color

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(Color.accentColor, in: .capsule)
                .shadow(radius: 4, y: 2)
        }
    }
}
