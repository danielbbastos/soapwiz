import Testing
import Foundation
@testable import SoapWiz

@Suite("Pro store – pending purchase")
@MainActor
struct ProStorePendingTests {

    private let hint: ProEntitlementHint
    private let backend = FakeProBackend()

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        hint = ProEntitlementHint(defaults: defaults)
        backend.outcome = .pending
    }

    private func makeStore() -> ProStore {
        ProStore(backend: backend, hint: hint)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func start_ChangeAfterPendingPurchase_UnlocksAndLeavesPending() async {
        let store = makeStore()
        store.start()
        await waitUntil { backend.isEntitledCalls >= 1 }

        _ = await store.purchase()
        #expect(store.purchaseState == .pending)

        backend.entitled = true
        backend.emitChange()
        await waitUntil { store.isPro }
        store.stop()

        #expect(store.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func refreshEntitlementHonouringCancellation_PendingNowEntitled_UnlocksAndLeavesPending() async {
        let store = makeStore()
        _ = await store.purchase()
        backend.entitled = true

        await store.refreshEntitlementHonouringCancellation()

        #expect(store.isPro)
        #expect(hint.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func refreshEntitlementHonouringCancellation_StillPending_StaysPending() async {
        let store = makeStore()
        _ = await store.purchase()

        await store.refreshEntitlementHonouringCancellation()

        #expect(!store.isPro)
        #expect(store.purchaseState == .pending)
    }
}
