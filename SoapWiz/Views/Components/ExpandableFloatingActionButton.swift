import SwiftUI

/// An action offered by an `ExpandableFloatingActionButton`, as a labelled pill.
struct FABAction: Identifiable {
    /// The stable id keeps each pill's measured size and animation attached to
    /// the same action across re-renders. Labels are unique within one button's
    /// actions.
    var id: String { label }
    let label: String
    let systemImage: String
    let action: () -> Void
}

/// What the expanded floating button shows and says, apart from how it is drawn.
enum FABLayout {
    /// The pills from the top of the screen down to the circle: the last
    /// secondary action first, the primary action last, nearest the button.
    static func pillOrder(primary: FABAction, secondary: [FABAction]) -> [FABAction] {
        secondary.reversed() + [primary]
    }

    /// How far the pill at `index` of `heights` (top to bottom) sits above the
    /// circle's centre: where it starts when it emerges and where it ends when
    /// it goes back.
    static func emergenceOffset(heights: [CGFloat], index: Int, spacing: CGFloat, diameter: CGFloat) -> CGFloat {
        guard heights.indices.contains(index) else { return 0 }
        let below = heights[(index + 1)...].reduce(0) { $0 + $1 + spacing }
        return heights[index] / 2 + spacing + below + diameter / 2
    }

    /// The wait before the pill at `index` of `count` (top to bottom) moves:
    /// the one nearest the circle first when opening, the top one first when
    /// closing.
    static func staggerDelay(index: Int, count: Int, isOpening: Bool, step: Double = 0.03) -> Double {
        Double(isOpening ? count - 1 - index : index) * step
    }

    static func circleLabel(hasSecondaryActions: Bool, isExpanded: Bool) -> String {
        guard hasSecondaryActions else { return String(localized: "Add") }
        return isExpanded ? String(localized: "Close") : String(localized: "Add, shows more actions")
    }
}

/// A floating `+` button. Tapping it performs the primary action, or, when
/// there are secondary actions, opens a vertical speed dial: a scrim over the
/// screen and a labelled pill for each action, the primary one nearest the
/// button. The `+` turns into an × that closes the dial. Long-pressing opens
/// it too.
struct ExpandableFloatingActionButton: View {
    let primaryLabel: String
    let primarySystemImage: String
    let primaryAction: () -> Void
    let secondaryActions: [FABAction]
    /// Beside the tab bar rather than above it: centred on the tab bar, measured
    /// from the bottom of the screen instead of the safe area the tab bar adds.
    var besideTabBar = false
    /// What the onboarding tour calls this button, where it points at it.
    var tourAnchor: TourAnchorID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var isExpanded = false
    /// Each pill's natural size, measured on a hidden copy so the first
    /// opening already knows how far to grow and slide.
    @State private var pillSizes: [String: CGSize] = [:]

    private let diameter: CGFloat = 56
    private let spacing: CGFloat = 12
    private let margin: CGFloat = 20

    private var pills: [FABAction] {
        FABLayout.pillOrder(
            primary: FABAction(label: primaryLabel, systemImage: primarySystemImage, action: primaryAction),
            secondary: secondaryActions
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Button(action: collapse) {
                    Color.paper.opacity(0.72)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: spacing) {
                pillStack
                circle
                    .tourAnchor(tourAnchor, cornerRadius: diameter / 2 + 6, outset: CGSize(width: 6, height: 6))
            }
            .padding(.horizontal, margin)
            .padding(.bottom, besideTabBar ? ListDetailLayout.tabBarCentreLine - diameter / 2 : margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .ignoresSafeArea(.container, edges: besideTabBar ? .bottom : [])
        }
        .background(alignment: .bottomTrailing) { sizeProbe }
    }

    private var sizeProbe: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(pills) { item in
                pillLabel(item)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSizes[item.id] = $0 }
            }
        }
        .padding(.horizontal, margin)
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var pillStack: some View {
        let order = pills
        let heights = order.map { pillSizes[$0.id]?.height ?? 48 }
        return VStack(alignment: .trailing, spacing: spacing) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, item in
                pill(item)
                    .modifier(FABPillEmergence(
                        progress: isExpanded ? 1 : 0,
                        width: pillSizes[item.id]?.width,
                        offset: FABLayout.emergenceOffset(
                            heights: heights, index: index, spacing: spacing, diameter: diameter
                        ),
                        diameter: diameter,
                        fadesOnly: reduceMotion
                    ))
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.15)
                            : reveal.delay(FABLayout.staggerDelay(index: index, count: order.count, isOpening: isExpanded)),
                        value: isExpanded
                    )
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private func pillLabel(_ item: FABAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .accessibilityHidden(true)
            Text(item.label)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .frame(minHeight: 48)
    }

    private func pill(_ item: FABAction) -> some View {
        Button {
            collapse()
            item.action()
        } label: {
            pillLabel(item)
                .contentShape(.capsule)
        }
        .buttonStyle(FABPillButtonStyle())
        .modifier(PillSurface(solid: reduceTransparency))
    }

    private var circle: some View {
        Image(systemName: "plus")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color.onAmber)
            .rotationEffect(.degrees(isExpanded ? 45 : 0))
            .frame(width: diameter, height: diameter)
            .modifier(CircleSurface())
            .shadow(color: .black.opacity(isExpanded ? 0.14 : 0.12),
                    radius: isExpanded ? 6 : 4,
                    y: isExpanded ? 3 : 2)
            .contentShape(.circle)
            .gesture(
                ExclusiveGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        guard !secondaryActions.isEmpty, !isExpanded else { return }
                        expand()
                    },
                    TapGesture().onEnded {
                        if isExpanded {
                            collapse()
                        } else if secondaryActions.isEmpty {
                            primaryAction()
                        } else {
                            expand()
                        }
                    }
                )
            )
            .accessibilityElement()
            .accessibilityLabel(FABLayout.circleLabel(hasSecondaryActions: !secondaryActions.isEmpty, isExpanded: isExpanded))
            .accessibilityAddTraits(.isButton)
    }

    private var reveal: Animation {
        .spring(response: 0.28, dampingFraction: 0.8)
    }

    private func expand() {
        withAnimation(reveal) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(reveal) {
            isExpanded = false
        }
    }
}

/// How far a pill is out of the circle, from 0 (on the circle: a capsule as
/// wide as the circle, hidden under it) to 1 (in its slot at full width). The
/// pill stays laid out in its slot throughout, so the stack never changes
/// size; the offset and a capsule mask over the whole pill, its trailing edge
/// fixed, do the moving and widening, and nothing is stretched. Without
/// motion it only fades. The pill's shadow is drawn by the stack around it,
/// so the mask doesn't clip it.
private struct FABPillEmergence: ViewModifier, Animatable {
    var progress: CGFloat
    let width: CGFloat?
    /// How far above the circle's centre the pill's slot is.
    let offset: CGFloat
    let diameter: CGFloat
    let fadesOnly: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if !fadesOnly, let width {
            let narrow = min(diameter, width)
            content
                .mask(alignment: .trailing) {
                    Capsule().frame(width: narrow + (width - narrow) * progress)
                }
                .offset(y: (1 - progress) * offset)
                .opacity(progress > 0.001 ? 1 : 0)
        } else {
            content.opacity(progress)
        }
    }
}

/// The pill's press feedback: the pressed honey tint fills a capsule over its
/// surface while the finger is down. The surface itself stays non-interactive.
private struct FABPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    Capsule().fill(Color.honeyPressed)
                }
            }
    }
}

/// The pill's capsule: glass on iOS 26 and a raised paper capsule before it,
/// or the raised paper on both when Reduce Transparency is on. The glass isn't
/// interactive: interactive glass renders white for its first half second.
private struct PillSurface: ViewModifier {
    let solid: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !solid, #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .capsule)
                .glassEffectTransition(.identity)
        } else {
            content
                .background(Color.paperRaised, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.rule, lineWidth: 1))
        }
    }
}

/// The circle behind the `+`: interactive amber glass on iOS 26, a solid
/// `amber` circle on earlier versions.
private struct CircleSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.floatingActionButton, in: .circle)
        } else {
            content.background(Color.amber, in: .circle)
        }
    }
}
