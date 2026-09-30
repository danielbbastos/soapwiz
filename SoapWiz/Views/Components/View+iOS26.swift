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

    /// Puts `strip` (a list's filter chips) under the navigation bar.
    /// `showsList` is false while an empty state stands in for the list.
    func headerStrip<Strip: View>(showsList: Bool, @ViewBuilder _ strip: () -> Strip) -> some View {
        modifier(HeaderStrip(showsList: showsList, strip: strip()))
    }
}

/// The strip itself has no background, so on iOS 26 the list keeps scrolling
/// under the navigation bar's material rather than under a flat band.
///
/// Earlier versions draw the strip over scrolled rows with nothing behind it.
/// There, once the list has scrolled, one bar material runs from the top of the
/// screen to the strip's bottom edge, and the navigation bar's own background
/// is hidden so the two don't stack with a seam between them. The strip is laid
/// out even when it has nothing to show, to carry that material under the bar.
///
/// Only the list reports its scrolling. An empty state that replaces it
/// reports nothing, so the scrolled state is dropped whenever the list comes
/// or goes: a list that returns starts at the top.
private struct HeaderStrip<Strip: View>: ViewModifier {
    let showsList: Bool
    let strip: Strip

    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0
            } action: { _, scrolled in
                isScrolled = scrolled
            }
            .onChange(of: showsList) {
                isScrolled = false
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if #available(iOS 26, *) {
                    strip
                } else {
                    VStack(spacing: 0) { strip }
                        .frame(maxWidth: .infinity)
                        .background {
                            Rectangle()
                                .fill(.bar)
                                .opacity(isScrolled ? 1 : 0)
                                .ignoresSafeArea(edges: .top)
                        }
                        .animation(.easeInOut(duration: 0.2), value: isScrolled)
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
    }
}
