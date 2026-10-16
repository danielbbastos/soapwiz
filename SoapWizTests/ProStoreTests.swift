import Testing
import Foundation
@testable import SoapWiz

@Suite("Pro store")
@MainActor
struct ProStoreTests {

    private let defaults: UserDefaults
    private let hint: ProEntitlementHint
    private let backend = FakeProBackend()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        hint = ProEntitlementHint(defaults: defaults)
    }

    private func makeStore() -> ProStore {
        ProStore(backend: backend, hint: hint)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func init_ReadsHint() {
        hint.isPro = true

        #expect(makeStore().isPro)
    }

    @Test func init_NoHint_IsNotPro() {
        #expect(!makeStore().isPro)
    }

    @Test func refreshEntitlement_Entitled_SetsIsProAndHint() async {
        let store = makeStore()
        backend.entitled = true

        await store.refreshEntitlement()

        #expect(store.isPro)
        #expect(hint.isPro)
    }

    @Test func refreshEntitlement_NotEntitled_ClearsIsProAndHint() async {
        hint.isPro = true
        let store = makeStore()
        backend.entitled = false

        await store.refreshEntitlement()

        #expect(!store.isPro)
        #expect(!hint.isPro)
    }

    @Test func start_LoadsEntitlementAndPrice() async {
        backend.entitled = true
        backend.price = "19,99 €"
        let store = makeStore()

        store.start()
        await waitUntil { store.isPro && store.displayPrice != nil }
        store.stop()

        #expect(store.isPro)
        #expect(store.displayPrice == "19,99 €")
    }

    @Test func start_ChangeEmitted_Refund_ClearsIsProAndHint() async {
        backend.entitled = true
        let store = makeStore()
        store.start()
        await waitUntil { store.isPro }
        #expect(hint.isPro)

        backend.entitled = false
        backend.emitChange()
        await waitUntil { !store.isPro }
        store.stop()

        #expect(!store.isPro)
        #expect(!hint.isPro)
    }

    @Test func start_ChangeEmitted_Purchase_SetsIsPro() async {
        let store = makeStore()
        store.start()

        backend.entitled = true
        backend.emitChange()
        await waitUntil { store.isPro }
        store.stop()

        #expect(store.isPro)
        #expect(hint.isPro)
    }

    @Test func start_CalledTwice_ListensOnce() async {
        let store = makeStore()

        store.start()
        store.start()
        backend.entitled = true
        backend.emitChange()
        await waitUntil { store.isPro }
        store.stop()

        #expect(backend.entitlementChangesCalls == 1)
        #expect(store.isPro)
    }

    @Test func start_AfterStop_ListensAgain() async {
        let store = makeStore()
        store.start()
        await waitUntil { backend.entitlementChangesCalls == 1 }
        store.stop()

        store.start()
        await waitUntil { backend.entitlementChangesCalls == 2 }
        backend.entitled = true
        backend.emitChange()
        await waitUntil { store.isPro }
        store.stop()

        #expect(backend.entitlementChangesCalls == 2)
        #expect(store.isPro)
    }

    @Test func start_StoppedMidRead_KeepsIsProAndHint() async {
        backend.entitled = true
        let store = makeStore()
        store.start()
        await waitUntil { backend.isEntitledCalls == 1 && store.isPro }
        backend.entitled = false
        backend.onIsEntitled = { store.stop() }

        backend.emitChange()
        await waitUntil { backend.isEntitledCalls == 2 }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.isPro)
        #expect(hint.isPro)
    }

    @Test func purchase_CallerCancelled_StillUnlocks() async {
        let store = makeStore()
        backend.outcome = .purchased
        var task: Task<ProPurchaseOutcome, Never>?
        backend.onPurchase = { task?.cancel() }

        task = Task { await store.purchase() }
        let outcome = await task?.value

        #expect(outcome == .purchased)
        #expect(store.isPro)
        #expect(hint.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func restore_CallerCancelled_StillApplies() async {
        let store = makeStore()
        backend.entitled = true
        var task: Task<Void, Never>?
        backend.onSync = { task?.cancel() }

        task = Task { try? await store.restore() }
        await task?.value

        #expect(store.isPro)
        #expect(hint.isPro)
    }

    @Test func entitlementChange_AfterPendingPurchase_ClearsPendingState() async {
        let store = makeStore()
        backend.outcome = .pending
        _ = await store.purchase()
        #expect(store.purchaseState == .pending)

        backend.entitled = true
        await store.refreshEntitlement()

        #expect(store.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func purchase_Purchased_RefreshesIsPro() async {
        let store = makeStore()
        backend.outcome = .purchased
        backend.entitled = true

        let outcome = await store.purchase()

        #expect(outcome == .purchased)
        #expect(store.isPro)
        #expect(hint.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func purchase_Cancelled_LeavesNotProAndIdle() async {
        let store = makeStore()
        backend.outcome = .cancelled

        let outcome = await store.purchase()

        #expect(outcome == .cancelled)
        #expect(!store.isPro)
        #expect(store.purchaseState == .idle)
    }

    @Test func purchase_Pending_LeavesNotProAndPending() async {
        let store = makeStore()
        backend.outcome = .pending

        let outcome = await store.purchase()

        #expect(outcome == .pending)
        #expect(!store.isPro)
        #expect(store.purchaseState == .pending)
    }

    @Test func purchase_Failed_LeavesNotProAndFailed() async {
        let store = makeStore()
        backend.outcome = .failed

        let outcome = await store.purchase()

        #expect(outcome == .failed)
        #expect(!store.isPro)
        #expect(store.purchaseState == .failed)
    }

    @Test func loadPrice_PriceAvailable_SetsDisplayPrice() async {
        let store = makeStore()
        backend.price = "19,99 €"

        await store.loadPrice()

        #expect(store.displayPrice == "19,99 €")
    }

    @Test func loadPrice_FetchFails_LeavesPriceNil() async {
        let store = makeStore()
        backend.price = nil

        await store.loadPrice()

        #expect(store.displayPrice == nil)
    }

    @Test func loadPrice_PriceKnown_DoesNotRefetchOrWipe() async {
        let store = makeStore()
        backend.price = "19,99 €"
        await store.loadPrice()
        backend.price = nil

        await store.loadPrice()

        #expect(store.displayPrice == "19,99 €")
        #expect(backend.displayPriceCalls == 1)
    }

    @Test func loadPrice_RetriesAfterFailure() async {
        let store = makeStore()
        backend.price = nil
        await store.loadPrice()
        backend.price = "9,99 €"

        await store.loadPrice()

        #expect(store.displayPrice == "9,99 €")
        #expect(backend.displayPriceCalls == 2)
    }

    @Test func loadPrice_FetchFails_SetsFailedFlag() async {
        let store = makeStore()
        backend.price = nil

        await store.loadPrice()

        #expect(store.priceLoadFailed)
    }

    @Test func loadPrice_RetryAfterFailure_SucceedsAndClearsFlag() async {
        let store = makeStore()
        backend.price = nil
        await store.loadPrice()
        backend.price = "9,99 €"

        await store.loadPrice()

        #expect(store.displayPrice == "9,99 €")
        #expect(!store.priceLoadFailed)
    }

    @Test func loadPrice_Concurrent_FetchesOnce() async {
        let store = makeStore()
        backend.price = "9,99 €"

        async let first: Void = store.loadPrice()
        async let second: Void = store.loadPrice()
        _ = await (first, second)

        #expect(backend.displayPriceCalls == 1)
        #expect(store.displayPrice == "9,99 €")
    }

    @Test func clearFailure_Failed_ReturnsToIdle() async {
        let store = makeStore()
        backend.outcome = .failed
        _ = await store.purchase()

        store.clearFailure()

        #expect(store.purchaseState == .idle)
    }

    @Test func clearFailure_Pending_StaysPending() async {
        let store = makeStore()
        backend.outcome = .pending
        _ = await store.purchase()

        store.clearFailure()

        #expect(store.purchaseState == .pending)
    }

    @Test func restore_SyncsThenRefreshes() async throws {
        let store = makeStore()
        backend.entitled = true

        try await store.restore()

        #expect(backend.syncCalls == 1)
        #expect(store.isPro)
        #expect(hint.isPro)
    }

    @Test func restore_SyncThrows_PropagatesAndKeepsState() async {
        let store = makeStore()
        backend.entitled = true
        backend.syncError = FakeProBackend.SyncFailure()

        await #expect(throws: FakeProBackend.SyncFailure.self) {
            try await store.restore()
        }

        #expect(!store.isPro)
    }
}
