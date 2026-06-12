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
/// grows it sideways into a capsule that holds the primary `+` alongside circular
/// buttons for each secondary action. Falls back to acting exactly like
/// `FloatingActionButton` when no secondary actions are supplied.
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

    @ViewBuilder private var control: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    secondaryButtons
                    plusButton
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        } else {
            HStack(spacing: 4) {
                secondaryButtons
                plusButton
            }
            .background(
                Capsule()
                    .fill(Color.accentColor)
                    .shadow(radius: 4, y: 2)
            )
        }
    }

    @ViewBuilder private var secondaryButtons: some View {
        if isExpanded {
            ForEach(secondaryActions) { item in
                iconButton(systemImage: item.systemImage, accessibility: item.label) {
                    collapse()
                    item.action()
                }
                .modifier(GlassCircle())
                .transition(.scale.combined(with: .opacity))
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isExpanded = false
        }
    }
}

/// Glass circle styling for the secondary buttons on iOS 26; a tinted circle on older OSes.
private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(Color.white.opacity(0.18), in: Circle())
        }
    }
}
