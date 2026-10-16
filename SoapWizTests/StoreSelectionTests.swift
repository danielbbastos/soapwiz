import Foundation
import Testing
@testable import SoapWiz

@Suite("Store selection")
@MainActor
struct StoreSelectionTests {

    @Test(arguments: [true, false], [true, false])
    func isOffline_AnyCombination_IsOfflineUnlessProAndSyncOn(isPro: Bool, prefersOffline: Bool) {
        #expect(StoreSelection.isOffline(isPro: isPro, prefersOffline: prefersOffline) == (!isPro || prefersOffline))
    }

    @Test(arguments: [true, false], [true, false])
    func localCause_AnyCombination_AgreesWithIsOffline(isPro: Bool, prefersOffline: Bool) {
        let cause = StoreSelection.localCause(isPro: isPro, prefersOffline: prefersOffline)
        #expect((cause != nil) == StoreSelection.isOffline(isPro: isPro, prefersOffline: prefersOffline))
    }

    @Test func localCause_FreeUser_IsRequiresProWhateverTheToggleSays() {
        #expect(StoreSelection.localCause(isPro: false, prefersOffline: false) == .requiresPro)
        #expect(StoreSelection.localCause(isPro: false, prefersOffline: true) == .requiresPro)
    }

    @Test func localCause_ProUserWithSyncOff_IsOfflineByChoice() {
        #expect(StoreSelection.localCause(isPro: true, prefersOffline: true) == .offlineByChoice)
    }

    @Test func localCause_ProUserWithSyncOn_IsNil() {
        #expect(StoreSelection.localCause(isPro: true, prefersOffline: false) == nil)
    }

    @Test func localStoreCause_MapsToItsActiveStore() {
        #expect(ModelContainerFactory.LocalStoreCause.requiresPro.activeStore == .requiresPro)
        #expect(ModelContainerFactory.LocalStoreCause.offlineByChoice.activeStore == .offlineByChoice)
    }

    @Test(arguments: [(Bool?.none, true), (true, false), (false, false)])
    func needsEntitlementWait_Hint_WaitsOnlyWhenNeverWritten(hint: Bool?, expected: Bool) {
        #expect(StoreSelection.needsEntitlementWait(hint: hint) == expected)
    }

    @Test(arguments: [Bool?.none, true, false], [Bool?.none, true, false])
    func launchIsPro_AnswerAndHint_AnswerWinsThenHintThenFalse(answer: Bool?, hint: Bool?) {
        let expected = answer ?? hint ?? false
        #expect(StoreSelection.launchIsPro(answer: answer, hint: hint) == expected)
    }

    @Test func launchIsPro_NeitherAnswerNorHint_IsFree() {
        #expect(!StoreSelection.launchIsPro(answer: nil, hint: nil))
    }

    @Test func launchIsPro_FreshAnswerContradictsHint_TrustsTheAnswer() {
        #expect(StoreSelection.launchIsPro(answer: false, hint: true) == false)
        #expect(StoreSelection.launchIsPro(answer: true, hint: false))
    }

    @Test(arguments: [true, false])
    func answer_FastRead_ReturnsIt(value: Bool) async {
        let result = await StoreSelection.answer(within: .seconds(5)) { value }

        #expect(result == value)
    }

    @Test func answer_ReadSlowerThanTimeout_ReturnsNil() async {
        let result = await StoreSelection.answer(within: .milliseconds(20)) {
            try? await Task.sleep(for: .seconds(30))
            return true
        }

        #expect(result == nil)
    }

    /// A read that ignores cancellation must not hold the caller: the wait is
    /// bounded by the clock, not by the slower of the two.
    @Test func answer_ReadIgnoringCancellation_StillReturnsNilAtTheTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now

        let result = await StoreSelection.answer(within: .milliseconds(50)) {
            await withCheckedContinuation { continuation in
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    continuation.resume(returning: true)
                }
            }
        }

        #expect(result == nil)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func timeout_IsPositive() {
        #expect(StoreSelection.entitlementTimeout > .zero)
    }
}

@Suite("Pro entitlement hint")
struct ProEntitlementHintTests {

    private let defaults: UserDefaults
    private let hint: ProEntitlementHint

    init() throws {
        defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        hint = ProEntitlementHint(defaults: defaults)
    }

    @Test func storedValue_NeverWritten_IsNil() {
        #expect(hint.storedValue == nil)
        #expect(!hint.isPro)
    }

    @Test(arguments: [true, false])
    func storedValue_AfterWrite_ReturnsIt(value: Bool) {
        hint.isPro = value

        #expect(hint.storedValue == value)
        #expect(hint.isPro == value)
    }
}

@Suite("Pro store timed answer")
@MainActor
struct ProStoreEntitlementAnswerTests {

    private let hint: ProEntitlementHint
    private let backend = FakeProBackend()

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        hint = ProEntitlementHint(defaults: defaults)
    }

    @Test(arguments: [true, false])
    func entitlementAnswer_AnsweredInTime_AppliesAndReturnsIt(entitled: Bool) async {
        let store = ProStore(backend: backend, hint: hint)
        backend.entitled = entitled

        let answer = await store.entitlementAnswer(within: .seconds(5))

        #expect(answer == entitled)
        #expect(store.isPro == entitled)
        #expect(hint.storedValue == entitled)
    }

    @Test func entitlementAnswer_TimesOut_ReturnsNilAndLeavesStateUntouched() async {
        let store = ProStore(backend: backend, hint: hint)
        backend.entitled = true
        backend.isEntitledDelay = .seconds(30)

        let answer = await store.entitlementAnswer(within: .milliseconds(20))

        #expect(answer == nil)
        #expect(!store.isPro)
        #expect(hint.storedValue == nil)
    }
}

@Suite("Sync relaunch notice")
struct SyncRelaunchNoticeTests {

    private let turnOff = "Close SoapWiz from the app switcher and open it again to turn off iCloud sync."
    private let turnBackOn = "Close SoapWiz from the app switcher and open it again to turn iCloud sync back on."
    private let start = "Close SoapWiz from the app switcher and open it again to start iCloud sync."

    @Test func text_MirroredAndProWithSyncOn_IsNil() {
        #expect(SyncRelaunchNotice.text(localCause: nil, isPro: true, prefersOffline: false) == nil)
    }

    @Test func text_MirroredAndUserTurnsSyncOff_AsksToTurnOff() {
        #expect(SyncRelaunchNotice.text(localCause: nil, isPro: true, prefersOffline: true) == turnOff)
    }

    @Test(arguments: [true, false])
    func text_MirroredButNoLongerPro_ShowsNothing(prefersOffline: Bool) {
        #expect(SyncRelaunchNotice.text(localCause: nil, isPro: false, prefersOffline: prefersOffline) == nil)
    }

    @Test func text_OfflineByChoiceAndUserTurnsSyncBackOn_AsksToTurnBackOn() {
        #expect(SyncRelaunchNotice.text(localCause: .offlineByChoice, isPro: true, prefersOffline: false) == turnBackOn)
    }

    @Test func text_OfflineByChoiceAndStillOff_IsNil() {
        #expect(SyncRelaunchNotice.text(localCause: .offlineByChoice, isPro: true, prefersOffline: true) == nil)
    }

    @Test func text_BoughtProWithSyncWanted_AsksToStartSync() {
        #expect(SyncRelaunchNotice.text(localCause: .requiresPro, isPro: true, prefersOffline: false) == start)
    }

    @Test func text_BoughtProButSyncStaysOff_IsNil() {
        #expect(SyncRelaunchNotice.text(localCause: .requiresPro, isPro: true, prefersOffline: true) == nil)
    }

    @Test(arguments: [true, false])
    func text_StillFree_IsNil(prefersOffline: Bool) {
        #expect(SyncRelaunchNotice.text(localCause: .requiresPro, isPro: false, prefersOffline: prefersOffline) == nil)
    }
}
