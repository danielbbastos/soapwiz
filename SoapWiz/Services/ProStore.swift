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
    /// True when the last price fetch finished without a price (offline).
    private(set) var priceLoadFailed = false
    private var isLoadingPrice = false

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
            await self?.refreshFromListener()
            await self?.loadPrice()
            for await _ in changes {
                await self?.refreshFromListener()
            }
        }
    }

    /// Fetches the price when none is known, so a launch that missed it (no
    /// connection) recovers when the user next opens a Pro screen. A failed
    /// fetch never clears a price already known.
    func loadPrice() async {
        guard displayPrice == nil, !isLoadingPrice else { return }
        isLoadingPrice = true
        priceLoadFailed = false
        defer { isLoadingPrice = false }
        if let price = await backend.displayPrice() {
            displayPrice = price
            priceLoadFailed = false
        } else {
            priceLoadFailed = true
        }
    }

    /// Forgets a failed purchase, so a reopened sheet doesn't greet the user
    /// with last time's error. A purchase waiting for approval stays.
    func clearFailure() {
        if purchaseState == .failed { purchaseState = .idle }
    }

    /// The only refresh that honours cancellation: `stop()` cancels the
    /// listener mid-read, and a cancelled `currentEntitlements` read can end
    /// early and report false. Purchase and restore run on a caller's task
    /// that may be cancelled after the user has paid, so they always apply.
    private func refreshFromListener() async {
        let entitled = await backend.isEntitled()
        guard !Task.isCancelled else { return }
        apply(entitled: entitled)
    }

    private func apply(entitled: Bool) {
        isPro = entitled
        hint.isPro = entitled
        if entitled { purchaseState = .idle }
    }

    /// Ends the listener, for tests and anything that must tear the store down.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The entitlement if StoreKit answers within `timeout`, applied like any
    /// refresh; `nil` otherwise, leaving the state as it was. The launch uses
    /// this on a fresh install, where the store can't be chosen without an answer.
    func entitlementAnswer(within timeout: Duration = StoreSelection.entitlementTimeout) async -> Bool? {
        let backend = backend
        let entitled = await StoreSelection.answer(within: timeout) { await backend.isEntitled() }
        // A cancelled read can end early and report false, as in `refreshFromListener`.
        guard let entitled, !Task.isCancelled else { return nil }
        apply(entitled: entitled)
        return entitled
    }

    func refreshEntitlement() async {
        apply(entitled: await backend.isEntitled())
    }

    func purchase() async -> ProPurchaseOutcome {
        purchaseState = .purchasing
        let outcome = await backend.purchase()
        switch outcome {
        case .purchased:
            apply(entitled: true)
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
