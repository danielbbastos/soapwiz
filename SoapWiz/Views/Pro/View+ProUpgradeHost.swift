import SwiftUI

extension View {
    /// Lets the upgrade sheet come up over this view. Apply it to the root of
    /// anything presented as a sheet or cover that can ask for an upgrade, and
    /// once at the bottom of the app.
    func proUpgradeHost() -> some View {
        modifier(ProUpgradeHostModifier())
    }
}

/// Registers the view as an upgrade host and attaches the sheet while it is
/// the topmost one. Does nothing without a presenter: the tour's sandbox has
/// no upgrade sheet.
private struct ProUpgradeHostModifier: ViewModifier {
    @Environment(ProUpgradePresenter.self) private var presenter: ProUpgradePresenter?
    @Environment(StoreHost.self) private var storeHost: StoreHost?
    @Environment(ProStore.self) private var proStore: ProStore?

    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        if let presenter, let storeHost, let proStore {
            content
                .sheet(item: request(of: presenter)) { request in
                    ProUpgradeView(reason: request.reason, offersSettings: presenter.isRootHost(hostID))
                        .environment(storeHost)
                        .environment(proStore)
                        .environment(presenter)
                }
                .onAppear { presenter.registerHost(hostID) }
                .onDisappear { presenter.unregisterHost(hostID) }
        } else {
            content
        }
    }

    private func request(of presenter: ProUpgradePresenter) -> Binding<ProUpgradeRequest?> {
        Binding(
            get: { presenter.isTopHost(hostID) ? presenter.request : nil },
            set: { if $0 == nil { presenter.dismiss() } }
        )
    }
}
