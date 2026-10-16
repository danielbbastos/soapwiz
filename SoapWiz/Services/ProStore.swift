import Foundation
import Observation

enum ProPurchaseState: Equatable {
    case idle
    case purchasing
    case pending
    case failed
}

/// Whether the user owns SoapWiz Pro, and how to buy it.
///
/// `isPro` starts from the last known answer so the interface isn't wrong
/// before StoreKit replies.
@Observable
final class ProStore {
    private(set) var isPro: Bool
    private(set) var displayPrice: String?
    private(set) var purchaseState: ProPurchaseState = .idle

    private let backend: any ProStoreBackend
    private let hint: ProEntitlementHint
    private var listener: Task<Void, Never>?

    init(
        backend: any ProStoreBackend = StoreKitProBackend(),
        hint: ProEntitlementHint = ProEntitlementHint()
    ) {
        self.backend = backend
        self.hint = hint
        self.isPro = hint.isPro
    }

    /// Reads the entitlement and price, then follows entitlement changes until
    /// `stop()`. Idempotent: the listener belongs to the store, not to any view
    /// or window, so a second call does nothing.
    func start() {
        guard listener == nil else { return }
        let changes = backend.entitlementChanges()
        listener = Task { [weak self] in
            await self?.refreshEntitlement()
            self?.displayPrice = await self?.backend.displayPrice()
            for await _ in changes {
                await self?.refreshEntitlement()
            }
        }
    }

    /// Ends the listener, for tests and anything that must tear the store down.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    func refreshEntitlement() async {
        let entitled = await backend.isEntitled()
        guard !Task.isCancelled else { return }
        isPro = entitled
        hint.isPro = entitled
        if entitled { purchaseState = .idle }
    }

    func purchase() async -> ProPurchaseOutcome {
        purchaseState = .purchasing
        let outcome = await backend.purchase()
        switch outcome {
        case .purchased:
            await refreshEntitlement()
            purchaseState = .idle
        case .pending:
            purchaseState = .pending
        case .cancelled:
            purchaseState = .idle
        case .failed:
            purchaseState = .failed
        }
        return outcome
    }

    func restore() async throws {
        try await backend.sync()
        await refreshEntitlement()
    }
}
