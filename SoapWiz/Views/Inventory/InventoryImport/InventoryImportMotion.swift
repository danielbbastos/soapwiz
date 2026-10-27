import SwiftUI

/// The motion of the spreadsheet import: one spring for every step change and
/// every row that moves, and with Reduce Motion a short ease-out and fades
/// without movement.
enum InventoryImportMotion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let reduced = Animation.easeOut(duration: 0.15)

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring
    }

    /// Runs a change to the import with the flow's animation, read from the
    /// system's Reduce Motion setting when it runs.
    static func animate(_ changes: () -> Void) {
        withAnimation(animation(reduceMotion: UIAccessibility.isReduceMotionEnabled), changes)
    }
}

enum InventoryImportTransition {
    /// A step of the flow: the new content comes in from the trailing edge and
    /// the old one leaves to the leading edge. Going back mirrors both.
    case step(isGoingBack: Bool)
    /// The amount field, which slides down from the button it replaces.
    case field
    /// A line that appears under a row: a fade with a slight move from the top.
    case reveal
}

extension View {
    func importTransition(_ kind: InventoryImportTransition) -> some View {
        modifier(InventoryImportTransitionModifier(kind: kind))
    }
}

private struct InventoryImportTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: InventoryImportTransition

    func body(content: Content) -> some View {
        content.transition(transition)
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch kind {
        case .step(let isGoingBack):
            let entering: Edge = isGoingBack ? .leading : .trailing
            let leaving: Edge = isGoingBack ? .trailing : .leading
            return .asymmetric(
                insertion: .move(edge: entering).combined(with: .opacity),
                removal: .move(edge: leaving).combined(with: .opacity)
            )
        case .field:
            return .move(edge: .top).combined(with: .opacity)
        case .reveal:
            return .offset(y: -8).combined(with: .opacity)
        }
    }
}
