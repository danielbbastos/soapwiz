import SwiftUI

/// Tags a collapsible section's header row, so the scroll rule has something
/// to aim at.
struct ExpandingSectionHeaderID: Hashable {
    let section: AnyHashable
}

/// A resolved scroll, handed back to the container to perform. The token makes
/// two identical requests distinct, so expanding the same section twice scrolls
/// both times.
struct ExpandingSectionScrollRequest: Equatable {
    let target: ExpandingSectionHeaderID
    let token: Int
}

/// Shared state behind "expanding a collapsible section scrolls it into view".
///
/// The rule, once a section has expanded: align its header with the top of the
/// viewport, which `scrollTo` places just below whatever covers the scroll
/// view's top edge. That reveals as much of the section as the screen can hold
/// without knowing where the section ends, so no row has to carry a marker.
@MainActor
@Observable
final class ExpandingSectionScrollContext {
    nonisolated static let spaceName = "ExpandingSectionScrollContainer"

    /// The scroll the container should perform next. The proxy is only valid
    /// inside the reader's body, so the decision is made here and carried out
    /// there.
    private(set) var request: ExpandingSectionScrollRequest?

    private let settleDelay: Duration
    private var pending: AnyHashable?
    private var settleTask: Task<Void, Never>?
    private var requestToken = 0

    init(settleDelay: Duration = .milliseconds(60)) {
        self.settleDelay = settleDelay
    }

    /// A section has started expanding. Its rows animate in, so the scroll
    /// waits for the header to stop moving rather than happening now.
    func expansionBegan(_ section: AnyHashable) {
        pending = section
        scheduleSettle(section)
    }

    /// A pending section's header moved: the page is still settling, so the
    /// wait starts over.
    func headerMoved(_ section: AnyHashable) {
        guard pending == section else { return }
        scheduleSettle(section)
    }

    private func scheduleSettle(_ section: AnyHashable) {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, pending == section else { return }
            pending = nil
            requestToken += 1
            request = ExpandingSectionScrollRequest(
                target: ExpandingSectionHeaderID(section: section),
                token: requestToken
            )
        }
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
                .onChange(of: context.request) { _, request in
                    guard let request else { return }
                    withAnimation { proxy.scrollTo(request.target, anchor: .top) }
                }
        }
        .coordinateSpace(name: ExpandingSectionScrollContext.spaceName)
    }
}

private struct ExpandingSectionHeader<ID: Hashable>: ViewModifier {
    let id: ID
    let expanded: Bool

    @Environment(\.expandingSectionScroll) private var context

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .named(ExpandingSectionScrollContext.spaceName)).minY
            } action: { _ in
                context?.headerMoved(AnyHashable(id))
            }
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

    /// Marks a collapsible section's header row, and scrolls it to the top of
    /// the container whenever `expanded` turns on. A `DisclosureGroup` is its
    /// own header: tag the group itself.
    func expandingSectionHeader(_ id: some Hashable, expanded: Bool) -> some View {
        // `.id` has to sit outermost: applied to a modifier's proxy content it
        // is not registered as a scroll target and `scrollTo` silently no-ops.
        modifier(ExpandingSectionHeader(id: id, expanded: expanded))
            .id(ExpandingSectionHeaderID(section: AnyHashable(id)))
    }
}
