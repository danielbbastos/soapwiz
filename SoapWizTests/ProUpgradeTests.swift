import Testing
import Foundation
import StoreKit
@testable import SoapWiz

@Suite("Pro upgrade presenter")
@MainActor
struct ProUpgradePresenterTests {

    private let sut = ProUpgradePresenter()

    @Test func present_NoReason_SetsRequestWithoutReason() {
        sut.registerHost(UUID())

        sut.present()

        #expect(sut.request != nil)
        #expect(sut.request?.reason == nil)
    }

    @Test func present_WithReason_KeepsReason() {
        sut.registerHost(UUID())

        sut.present(reason: .sync)

        #expect(sut.request?.reason == .sync)
    }

    @Test func present_NoHost_StoresNoRequest() {
        sut.present(reason: .recipeLimit)

        #expect(sut.request == nil)
    }

    @Test func present_NoHost_DoesNotSurfaceWhenAHostRegistersLater() {
        sut.present(reason: .recipeLimit)

        sut.registerHost(UUID())

        #expect(sut.request == nil)
    }

    @Test func unregisterHost_LastHostWithPendingRequest_ClearsRequest() {
        let root = UUID()
        sut.registerHost(root)
        sut.present(reason: .reminders)

        sut.unregisterHost(root)

        #expect(sut.request == nil)
    }

    @Test func unregisterHost_OneOfTwoHostsWithPendingRequest_KeepsRequest() {
        let root = UUID()
        let sheet = UUID()
        sut.registerHost(root)
        sut.registerHost(sheet)
        sut.present(reason: .reminders)

        sut.unregisterHost(sheet)

        #expect(sut.request != nil)
    }

    @Test func dismiss_ClearsRequest() {
        sut.registerHost(UUID())
        sut.present(reason: .reminders)

        sut.dismiss()

        #expect(sut.request == nil)
    }

    @Test func present_Twice_ReplacesRequestWithNewId() throws {
        sut.registerHost(UUID())
        sut.present(reason: .collections)
        let first = try #require(sut.request)

        sut.present(reason: .collections)
        let second = try #require(sut.request)

        #expect(first.id != second.id)
    }

    @Test func dismissToSettings_ClearsRequestAndSignalsSettings() {
        sut.registerHost(UUID())
        sut.present()
        let before = sut.settingsRequest

        sut.dismissToSettings()

        #expect(sut.request == nil)
        #expect(sut.settingsRequest != nil)
        #expect(sut.settingsRequest != before)
    }

    // MARK: Hosts

    @Test func topHost_NoHosts_IsNil() {
        #expect(sut.topHostID == nil)
    }

    @Test func registerHost_LatestRegisteredIsTopmost() {
        let root = UUID()
        let sheet = UUID()

        sut.registerHost(root)
        sut.registerHost(sheet)

        #expect(sut.isTopHost(sheet))
        #expect(!sut.isTopHost(root))
    }

    @Test func registerHost_SameHostTwice_IsStoredOnce() {
        let root = UUID()

        sut.registerHost(root)
        sut.registerHost(root)

        #expect(sut.hostIDs == [root])
    }

    @Test func unregisterHost_TopHost_PopsToTheOneBelow() {
        let root = UUID()
        let sheet = UUID()
        sut.registerHost(root)
        sut.registerHost(sheet)

        sut.unregisterHost(sheet)

        #expect(sut.isTopHost(root))
        #expect(sut.hostIDs == [root])
    }

    @Test func unregisterHost_OutOfOrder_KeepsTheTopmostOnTop() {
        let root = UUID()
        let middle = UUID()
        let top = UUID()
        sut.registerHost(root)
        sut.registerHost(middle)
        sut.registerHost(top)

        sut.unregisterHost(middle)

        #expect(sut.hostIDs == [root, top])
        #expect(sut.isTopHost(top))
    }

    @Test func unregisterHost_Unknown_ChangesNothing() {
        let root = UUID()
        sut.registerHost(root)

        sut.unregisterHost(UUID())

        #expect(sut.hostIDs == [root])
    }

    @Test func unregisterHost_LastHost_LeavesNoTop() {
        let root = UUID()
        sut.registerHost(root)

        sut.unregisterHost(root)

        #expect(sut.topHostID == nil)
    }

    @Test func isRootHost_OnlyTheBottomOne() {
        let root = UUID()
        let sheet = UUID()
        sut.registerHost(root)
        sut.registerHost(sheet)

        #expect(sut.isRootHost(root))
        #expect(!sut.isRootHost(sheet))
    }

    @Test func isRootHost_AfterTheRootLeaves_NextBecomesRoot() {
        let root = UUID()
        let sheet = UUID()
        sut.registerHost(root)
        sut.registerHost(sheet)

        sut.unregisterHost(root)

        #expect(sut.isRootHost(sheet))
    }
}

@Suite("Pro upgrade copy")
struct ProUpgradeCopyTests {

    @Test func message_RecipeLimit_IncludesCap() {
        #expect(ProUpgradeReason.recipeLimit.message.contains("\(FreeTierLimits.recipeCap)"))
    }

    @Test func message_CustomIngredientLimit_IncludesCap() {
        #expect(ProUpgradeReason.customIngredientLimit.message.contains("\(FreeTierLimits.customIngredientCap)"))
    }

    @Test func message_FeatureReasons_NameTheFeature() {
        #expect(ProUpgradeReason.sync.message.contains("iCloud sync"))
        #expect(ProUpgradeReason.collections.message.contains("Collections"))
        #expect(ProUpgradeReason.reminders.message.contains("Reminders"))
    }

    @Test func buttonTitle_Idle_UnlockWithPrice() {
        #expect(ProUpgradeButton.title(price: "X", state: .idle) == "Unlock Pro · X")
    }

    @Test func buttonTitle_NoPrice_PlainUnlock() {
        #expect(ProUpgradeButton.title(price: nil, state: .idle) == "Unlock Pro")
    }

    @Test func buttonTitle_Failed_TryAgainWithPrice() {
        #expect(ProUpgradeButton.title(price: "X", state: .failed) == "Try again · X")
    }

    @Test func isEnabled_NoPrice_Disabled() {
        #expect(!ProUpgradeButton.isEnabled(price: nil, state: .idle))
    }

    @Test func isEnabled_WhileRestoring_Disabled() {
        #expect(!ProUpgradeButton.isEnabled(price: "X", state: .idle, isRestoring: true))
    }

    @Test func canRestore_PerState() {
        #expect(ProUpgradeButton.canRestore(isRestoring: false, state: .idle))
        #expect(ProUpgradeButton.canRestore(isRestoring: false, state: .pending))
        #expect(!ProUpgradeButton.canRestore(isRestoring: false, state: .purchasing))
        #expect(!ProUpgradeButton.canRestore(isRestoring: true, state: .idle))
    }

    @Test func isEnabled_PerState() {
        #expect(ProUpgradeButton.isEnabled(price: "X", state: .idle))
        #expect(ProUpgradeButton.isEnabled(price: "X", state: .failed))
        #expect(!ProUpgradeButton.isEnabled(price: "X", state: .purchasing))
        #expect(!ProUpgradeButton.isEnabled(price: "X", state: .pending))
    }

    @Test func usesGrid_PhoneWidths_UsesList() {
        #expect(!ProUpgradeLayout.usesGrid(width: 0))
        #expect(!ProUpgradeLayout.usesGrid(width: 393))
        #expect(!ProUpgradeLayout.usesGrid(width: 430))
    }

    @Test func usesGrid_FormSheetWidth_UsesGrid() {
        #expect(ProUpgradeLayout.usesGrid(width: ProUpgradeLayout.gridMinimumWidth))
        #expect(ProUpgradeLayout.usesGrid(width: 540))
    }

    @Test func syncOutcome_SyncOn_StartsOnRelaunch() {
        #expect(ProSyncOutcome(prefersOffline: false) == .startsOnRelaunch)
    }

    @Test func syncOutcome_SyncOff_IsOff() {
        #expect(ProSyncOutcome(prefersOffline: true) == .isOff)
    }
}

@Suite("Pro restore")
@MainActor
struct ProRestoreModelTests {

    private let backend = FakeProBackend()
    private let hint: ProEntitlementHint

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        hint = ProEntitlementHint(defaults: defaults)
    }

    @Test func restore_Entitled_AlertsRestored() async {
        let store = ProStore(backend: backend, hint: hint)
        let sut = ProRestoreModel()
        backend.entitled = true

        await sut.restore(using: store)

        #expect(sut.alert == .restored)
        #expect(store.isPro)
        #expect(!sut.isRestoring)
    }

    @Test func restore_EntitledWithoutAnnouncing_NoAlert() async {
        let store = ProStore(backend: backend, hint: hint)
        let sut = ProRestoreModel()
        backend.entitled = true

        await sut.restore(using: store, announcesSuccess: false)

        #expect(sut.alert == nil)
        #expect(store.isPro)
    }

    @Test func restore_NothingFound_AlertsNothingFound() async {
        let store = ProStore(backend: backend, hint: hint)
        let sut = ProRestoreModel()

        await sut.restore(using: store)

        #expect(sut.alert == .nothingFound)
    }

    @Test func restore_UserCancelled_StaysSilent() async {
        let store = ProStore(backend: backend, hint: hint)
        let sut = ProRestoreModel()
        backend.syncError = StoreKitError.userCancelled

        await sut.restore(using: store)

        #expect(sut.alert == nil)
        #expect(!sut.isRestoring)
    }

    @Test func restore_SyncThrows_AlertsFailure() async {
        let store = ProStore(backend: backend, hint: hint)
        let sut = ProRestoreModel()
        backend.syncError = FakeProBackend.SyncFailure()

        await sut.restore(using: store)

        guard case .failed = sut.alert else {
            Issue.record("Expected a failed alert, got \(String(describing: sut.alert))")
            return
        }
    }
}
