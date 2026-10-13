import SwiftUI

/// Liquid Glass made dense with a `paperRaised` tint, so the list behind reads
/// only as a soft blur; solid `paperRaised` with Reduce Transparency.
struct CostBarSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        fill(content)
            .overlay(shape.strokeBorder(reduceTransparency ? Color.rule : Color.glassEdge, lineWidth: 1))
            .shadow(color: Color.shadow.opacity(colorScheme == .dark ? 0.40 : 0.16), radius: 10, y: 6)
    }

    @ViewBuilder
    private func fill(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.paperRaised, in: shape)
        } else if #available(iOS 26, *) {
            content
                .background(Color.paperRaised.opacity(0.78), in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
