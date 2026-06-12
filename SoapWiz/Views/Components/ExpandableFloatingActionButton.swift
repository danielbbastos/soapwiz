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

/// A floating `+` button whose tap performs the primary action, and whose
/// long-press expands to reveal labelled secondary actions stacked above it.
/// Falls back to acting exactly like `FloatingActionButton` when no secondary
/// actions are supplied.
struct ExpandableFloatingActionButton: View {
    let primaryAction: () -> Void
    let secondaryActions: [FABAction]

    @State private var isExpanded = false

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

            VStack(alignment: .trailing, spacing: 12) {
                if isExpanded {
                    ForEach(secondaryActions) { item in
                        secondaryButton(item)
                    }
                }
                mainButton
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }

    private var mainButton: some View {
        Button {
            if isExpanded {
                collapse()
            } else {
                primaryAction()
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
                .frame(width: 56, height: 56)
        }
        .modifier(FABStyle())
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                guard !secondaryActions.isEmpty else { return }
                expand()
            }
        )
    }

    private func secondaryButton(_ item: FABAction) -> some View {
        Button {
            collapse()
            item.action()
        } label: {
            HStack(spacing: 10) {
                Text(item.label)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: item.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
        }
        .modifier(SecondaryFABStyle())
        .transition(.move(edge: .trailing).combined(with: .opacity))
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

private struct FABStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
    }
}

private struct SecondaryFABStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding(.leading, 16)
                .foregroundStyle(Color.warmInk)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .padding(.leading, 16)
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(Capsule())
                .shadow(radius: 4, y: 2)
        }
    }
}
