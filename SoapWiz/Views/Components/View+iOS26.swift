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
    /// The add buttons' amber glass. `GlassAmber` carries its own opacity per
    /// appearance, so the list shows through in both.
    static var floatingActionButton: Glass {
        .clear.tint(Color.glassAmber).interactive()
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

    /// Earlier versions have no glass to give the field an edge, so it is a
    /// raised paper shape with a `rule` stroke and a soft shadow.
    @ViewBuilder
    func glassEffectInteractiveIOS26<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.ledgerRaisedSurface(in: shape)
        }
    }

    /// Regular Liquid Glass button style on iOS 26 (light/translucent with a
    /// tinted label), falling back to an opaque raised paper capsule on earlier
    /// versions, where `.bordered` is a flat grey box the content shows through.
    /// For call-to-action buttons on the navigation layer that shouldn't
    /// dominate with a solid fill.
    @ViewBuilder
    func glassButtonStyleIOS26() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(LedgerRaisedCapsuleButtonStyle())
        }
    }

    /// Puts `strip` (a list's search field and filter chips) under the
    /// navigation bar.
    /// `showsList` is false while an empty state stands in for the list.
    func headerStrip<Strip: View>(showsList: Bool, @ViewBuilder _ strip: () -> Strip) -> some View {
        modifier(HeaderStrip(showsList: showsList, strip: strip()))
    }
}

/// The strip itself has no background, so on iOS 26 the list keeps scrolling
/// under the navigation bar's material rather than under a flat band.
///
/// Earlier versions draw the strip over scrolled rows with nothing behind it.
/// There, once the list has scrolled, the paper runs from the top of the screen
/// to the strip's bottom edge, with a `rule` hairline along that edge, and the
/// navigation bar's own background is hidden so the two don't stack with a seam
/// between them. The strip is laid out even when it has nothing to show, to
/// carry that paper under the bar.
///
/// Earlier versions also have no large-title subtitle slot, so the subtitle
/// `ledgerLargeTitle` was given, and the ornament that goes with it, sit at the
/// top of the strip, and collapse once the list has scrolled, as the large title
/// does. Collapsing shrinks the strip, and with it the scroll view's top inset,
/// which moves the very value that decides whether the list has scrolled. So
/// the two ends are separate: the subtitle collapses only once the list has
/// scrolled past its own height with a margin to spare, and comes back only
/// when the list is back at the top. A collapse takes the value down by the
/// subtitle's height at most, which still leaves it above the top, and the
/// return takes it up by the same, which still leaves it below the collapsing
/// point, so neither end can undo the other however slowly a finger drags
/// across.
///
/// Only the list reports its scrolling. An empty state that replaces it
/// reports nothing, so the scrolled state is dropped whenever the list comes
/// or goes: a list that returns starts at the top.
private struct HeaderStrip<Strip: View>: ViewModifier {
    let showsList: Bool
    let strip: Strip

    @State private var isScrolled = false
    @State private var titleInfo: LedgerLargeTitleInfo?
    @State private var isSubtitleCollapsed = false
    @State private var subtitleHeight: CGFloat = 0

    /// How far past the subtitle's own height the list scrolls before it
    /// collapses.
    private let collapseMargin: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .environment(\.ledgerHasHeaderStrip, true)
            .preference(key: LedgerHasHeaderStripPreference.self, value: true)
            .onPreferenceChange(LedgerLargeTitleInfoKey.self) { newInfo in
                titleInfo = newInfo
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                (geometry.contentOffset.y + geometry.contentInsets.top).rounded()
            } action: { _, offset in
                isScrolled = offset > 0
                if isSubtitleCollapsed {
                    if offset <= 0 { isSubtitleCollapsed = false }
                } else if offset > subtitleHeight + collapseMargin {
                    isSubtitleCollapsed = true
                }
            }
            .onChange(of: showsList) {
                isScrolled = false
                isSubtitleCollapsed = false
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if #available(iOS 26, *) {
                    strip
                } else {
                    LegacyHeaderStrip(
                        strip: strip,
                        isScrolled: isScrolled,
                        titleInfo: titleInfo,
                        isSubtitleCollapsed: isSubtitleCollapsed,
                        subtitleHeight: $subtitleHeight
                    )
                }
            }
    }
}

/// The strip as earlier versions draw it: the subtitle and its ornament above
/// `strip`, on a band of paper that appears once the list has scrolled.
private struct LegacyHeaderStrip<Strip: View>: View {
    let strip: Strip
    let isScrolled: Bool
    let titleInfo: LedgerLargeTitleInfo?
    let isSubtitleCollapsed: Bool
    @Binding var subtitleHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let subtitle = titleInfo?.subtitle, !isSubtitleCollapsed {
                HeaderStripSubtitle(text: subtitle, leading: titleInfo?.titleLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        subtitleHeight = height
                    }
                    .transition(.opacity)
            }
            strip
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background {
            // The paper ignores every safe area itself, so it is
            // clipped to this band, which is taken up under the bar.
            Color.clear
                .overlay { HoneyLedgerPaper() }
                .clipped()
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.rule)
                        .frame(height: 1)
                }
                .opacity(isScrolled ? 1 : 0)
                .ignoresSafeArea(edges: .top)
        }
        .animation(.easeInOut(duration: 0.2), value: isScrolled)
        .animation(.easeInOut(duration: 0.2), value: isSubtitleCollapsed)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// What `ledgerLargeTitle` tells the strip: the subtitle it was given, which
/// the strip shows where earlier versions have no slot under the large title,
/// and how far in from the edge of the screen the title's text starts, which
/// that subtitle lines up with.
struct LedgerLargeTitleInfo: Equatable {
    var subtitle: String?
    var titleLeading: CGFloat?
}

struct LedgerLargeTitleInfoKey: PreferenceKey {
    static let defaultValue: LedgerLargeTitleInfo? = nil

    static func reduce(value: inout LedgerLargeTitleInfo?, nextValue: () -> LedgerLargeTitleInfo?) {
        value = nextValue() ?? value
    }
}

/// Whether the screen has a `headerStrip`, which draws the paper behind the
/// navigation bar itself once the list has scrolled.
private struct LedgerHasHeaderStripKey: EnvironmentKey {
    static let defaultValue = false
}

/// The same fact for the screens that set their title outside the strip, which
/// the environment doesn't reach.
struct LedgerHasHeaderStripPreference: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    var ledgerHasHeaderStrip: Bool {
        get { self[LedgerHasHeaderStripKey.self] }
        set { self[LedgerHasHeaderStripKey.self] = newValue }
    }
}

/// `LedgerSubtitleView`'s count line and ornament as the strip draws them: the
/// footnote in `inkSoft`, then an 8pt amber diamond with a hairline running off
/// to the trailing edge. Lined up with the large title's text when `leading`,
/// its distance from the edge, is known, and with the search field below it
/// until then.
private struct HeaderStripSubtitle: View {
    let text: String
    let leading: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.inkSoft)
            HoneyLedgerDiamondRule()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: leading == nil ? ReadableWidth.maximum : .infinity, alignment: .leading)
        .padding(.horizontal, leading ?? 16)
        .padding(.bottom, 12)
    }
}

/// Earlier versions' fallback for the glass button: an opaque raised paper
/// capsule with a `rule` edge and a soft shadow, at `.bordered` large metrics.
/// The label keeps any foreground style it sets, and is `amberText` otherwise.
private struct LedgerRaisedCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.amberText)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 50)
            .ledgerRaisedSurface(configuration.isPressed ? Color.honeyPressed : Color.paperRaised, in: Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.capsule)
    }
}
