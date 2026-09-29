import SwiftUI

struct GlassEffectContainerIOS26<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

@available(iOS 26, *)
extension Glass {
    /// The add buttons' yellow glass. `FABTint` carries its own opacity per
    /// appearance: light mode's darker accent needs less of it to let the list
    /// show through.
    static var floatingActionButton: Glass {
        .clear.tint(Color.fabTint).interactive()
    }
}

extension View {
    @ViewBuilder
    func glassEffectIOS26<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func glassEffectInteractiveIOS26<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Regular Liquid Glass button style on iOS 26 (light/translucent with a
    /// tinted label), falling back to `.bordered` on earlier versions. For
    /// call-to-action buttons on the navigation layer that shouldn't dominate
    /// with a solid fill.
    @ViewBuilder
    func glassButtonStyleIOS26() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
