import Foundation
@testable import SoapWiz

@MainActor
final class FakeProBackend: ProStoreBackend {
    struct SyncFailure: Error {}

    var entitled = false
    var price: String?
    var outcome: ProPurchaseOutcome = .purchased
    var syncError: (any Error)?
    var onIsEntitled: (() -> Void)?
    var onPurchase: (() -> Void)?
    var onSync: (() -> Void)?
    private(set) var isEntitledCalls = 0
    private(set) var syncCalls = 0
    private(set) var displayPriceCalls = 0
    private(set) var entitlementChangesCalls = 0

    private var continuation: AsyncStream<Void>.Continuation?

    func isEntitled() async -> Bool {
        isEntitledCalls += 1
        onIsEntitled?()
        return entitled
    }

    func entitlementChanges() -> AsyncStream<Void> {
        entitlementChangesCalls += 1
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.continuation = continuation
        return stream
    }

    func emitChange() {
        continuation?.yield()
    }

    func displayPrice() async -> String? {
        displayPriceCalls += 1
        await Task.yield()
        return price
    }

    func purchase() async -> ProPurchaseOutcome {
        onPurchase?()
        return outcome
    }

    func sync() async throws {
        syncCalls += 1
        onSync?()
        if let syncError { throw syncError }
    }
}
