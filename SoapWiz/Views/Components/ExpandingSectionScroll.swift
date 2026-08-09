import SwiftUI

/// Tags the row that marks a collapsible section's top or bottom edge, so the
/// scroll rule has something to aim at.
private struct ExpandingSectionEdgeID: Hashable {
    let section: AnyHashable
    let isEnd: Bool
}

/// A resolved scroll, handed back to the container to perform. The token makes
/// two identical requests distinct, so expanding the same section twice scrolls
/// both times.
private struct ExpandingSectionScrollRequest: Equatable {
    let target: ExpandingSectionEdgeID
    let anchor: UnitPoint
    let token: Int
}

/// Shared state behind "expanding a collapsible section scrolls it into view".
///
/// The rule, once a section has expanded: reveal as much of it as possible —
/// align its bottom with the bottom of the viewport when the whole section
/// fits, its top with the top of the viewport when it doesn't, and leave the
/// page alone when the section is already fully visible.
///
/// The container publishes the region of itself that is actually visible and
/// carries out the scroll; each section reports the frames of its first and
/// last row. A section that never reports a last row falls back to
/// top-alignment, which is also what a section taller than the viewport gets.
@MainActor
@Observable
final class ExpandingSectionScrollContext {
    nonisolated static let spaceName = "ExpandingSectionScrollContainer"

    /// The scroll the container should perform next. The proxy is only valid
    /// inside the reader's body, so the decision is made here and carried out
    /// there.
    fileprivate var request: ExpandingSectionScrollRequest?

    /// The visible span of the container, in its own coordinates: inset at the
    /// top by the navigation bar and at the bottom by the tab bar and whatever
    /// the screen pins over it.
    fileprivate var visible: ClosedRange<CGFloat> = 0...0
    /// Top edge of a panel that covers the scroll view's bottom instead of
    /// insetting it — the recipe form's cost bar, which grows over the list
    /// without the scroll view's content insets ever hearing about it.
    fileprivate var overlayTop: CGFloat?
    fileprivate var headers: [AnyHashable: CGRect] = [:]
    fileprivate var footers: [AnyHashable: CGRect] = [:]
    /// Sections whose header row already contains the whole section — a
    /// `DisclosureGroup` — and so are their own bottom edge. A separate end tag
    /// nested inside such a row is not reachable as a scroll target.
    fileprivate var wholeSections: Set<AnyHashable> = []

    private var pending: AnyHashable?
    private var settleTask: Task<Void, Never>?
    private var requestToken = 0

    /// `scrollTo` positions a row including the list's spacing around it, which
    /// the measured frames don't cover. A section that only just fits would
    /// otherwise be bottom-aligned and lose its header off the top, so it has
    /// to clear the viewport by this much before it counts as fitting.
    private static let fitAllowance: CGFloat = 24

    /// A section has started expanding. Its rows animate in, so the geometry is
    /// read once it stops moving rather than now.
    fileprivate func expansionBegan(_ section: AnyHashable) {
        pending = section
        scheduleSettle(section)
    }

    /// One of a pending section's edges moved — the expansion is still playing
    /// out, so the wait starts over.
    fileprivate func edgeMoved(_ section: AnyHashable) {
        guard pending == section else { return }
        scheduleSettle(section)
    }

    private func scheduleSettle(_ section: AnyHashable) {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, pending == section else { return }
            pending = nil
            scrollIntoView(section)
        }
    }

    private func scrollIntoView(_ section: AnyHashable) {
        let visibleBottom = min(visible.upperBound, overlayTop ?? .greatestFiniteMagnitude)
        let visibleHeight = visibleBottom - visible.lowerBound
        guard let top = headers[section]?.minY, visibleHeight > 0 else { return }
        let bottom = footers[section]?.maxY

        // Without a last row the section's extent is unknown, so it is treated
        // as overflowing: aligning the top is the safe reveal either way.
        let fits = bottom.map { $0 - top <= visibleHeight - Self.fitAllowance } ?? false
        let fullyVisible = top >= visible.lowerBound && (bottom.map { $0 <= visibleBottom } ?? false)
        guard !fullyVisible else { return }

        requestToken += 1
        request = ExpandingSectionScrollRequest(
            target: ExpandingSectionEdgeID(
                section: section, isEnd: fits && !wholeSections.contains(section)
            ),
            anchor: fits ? .bottom : .top,
            token: requestToken
        )
    }
}

extension EnvironmentValues {
    @Entry var expandingSectionScroll: ExpandingSectionScrollContext?
}

private struct ExpandingSectionScrollContainer: ViewModifier {
    @State private var context = ExpandingSectionScrollContext()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.expandingSectionScroll, context)
                // `contentInsets` already covers the navigation bar, the tab
                // bar and any `safeAreaInset` the screen pins over the scroll
                // view, and tracks the cost bar as it grows.
                .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
                    let bottom = geometry.containerSize.height - geometry.contentInsets.bottom
                    return geometry.contentInsets.top...max(geometry.contentInsets.top, bottom)
                } action: { _, visible in
                    context.visible = visible
                }
                .onChange(of: context.request) { _, request in
                    guard let request else { return }
                    withAnimation { proxy.scrollTo(request.target, anchor: request.anchor) }
                }
        }
        .coordinateSpace(name: ExpandingSectionScrollContext.spaceName)
    }
}

private struct ExpandingSectionScrollOverlay: ViewModifier {
    @Environment(\.expandingSectionScroll) private var context

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .named(ExpandingSectionScrollContext.spaceName)).minY
            } action: { context?.overlayTop = $0 }
    }
}

private struct ExpandingSectionEdge<ID: Hashable>: ViewModifier {
    let id: ID
    let isEnd: Bool
    var spansWholeSection = false

    @Environment(\.expandingSectionScroll) private var context

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(ExpandingSectionScrollContext.spaceName))
            } action: { frame in
                let section = AnyHashable(id)
                if isEnd {
                    context?.footers[section] = frame
                } else {
                    context?.headers[section] = frame
                    if spansWholeSection {
                        context?.wholeSections.insert(section)
                        context?.footers[section] = frame
                    }
                }
                context?.edgeMoved(section)
            }
    }
}

private struct ExpandingSectionHeader<ID: Hashable>: ViewModifier {
    let id: ID
    let expanded: Bool
    let spansWholeSection: Bool

    @Environment(\.expandingSectionScroll) private var context

    func body(content: Content) -> some View {
        content
            .modifier(ExpandingSectionEdge(id: id, isEnd: false, spansWholeSection: spansWholeSection))
            .onChange(of: expanded) { _, isExpanded in
                guard isExpanded else { return }
                context?.expansionBegan(AnyHashable(id))
            }
    }
}

extension View {
    /// Marks the scroll container that collapsible sections inside it scroll
    /// within.
    func expandingSectionScrollContainer() -> some View {
        modifier(ExpandingSectionScrollContainer())
    }

    /// Marks a panel that covers the container's bottom edge rather than
    /// insetting it, so sections are not aligned to a bottom that is hidden
    /// behind it.
    func expandingSectionScrollOverlay() -> some View {
        modifier(ExpandingSectionScrollOverlay())
    }

    /// Marks a collapsible section's header row, and scrolls the section into
    /// view whenever `expanded` turns on. Set `spansWholeSection` when the
    /// header view contains the section's content too, as a `DisclosureGroup`
    /// does — it then needs no separate end tag.
    func expandingSectionHeader(
        _ id: some Hashable, expanded: Bool, spansWholeSection: Bool = false
    ) -> some View {
        // `.id` has to sit outermost: applied to a modifier's proxy content it
        // is not registered as a scroll target and `scrollTo` silently no-ops.
        modifier(
            ExpandingSectionHeader(id: id, expanded: expanded, spansWholeSection: spansWholeSection)
        )
        .id(ExpandingSectionEdgeID(section: AnyHashable(id), isEnd: false))
    }

    /// Marks a collapsible section's last row, without which the section can
    /// only be top-aligned.
    func expandingSectionEnd(_ id: some Hashable) -> some View {
        modifier(ExpandingSectionEdge(id: id, isEnd: true))
            .id(ExpandingSectionEdgeID(section: AnyHashable(id), isEnd: true))
    }

    /// Marks the last row only when `condition` holds, for sections whose final
    /// row depends on what they contain.
    @ViewBuilder
    func expandingSectionEnd(_ id: some Hashable, if condition: Bool) -> some View {
        if condition { expandingSectionEnd(id) } else { self }
    }
}
