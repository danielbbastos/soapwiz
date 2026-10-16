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
    private var isStarted = false

    init(
        backend: any ProStoreBackend = StoreKitProBackend(),
        hint: ProEntitlementHint = ProEntitlementHint()
    ) {
        self.backend = backend
        self.hint = hint
        self.isPro = hint.isPro
    }

    /// Reads the entitlement and price, then follows entitlement changes for as
    /// long as the calling task lives. A second call returns at once.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        let changes = backend.entitlementChanges()
        await refreshEntitlement()
        displayPrice = await backend.displayPrice()
        for await _ in changes {
            await refreshEntitlement()
        }
    }

    func refreshEntitlement() async {
        isPro = await backend.isEntitled()
        hint.isPro = isPro
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
