import Testing
import CloudKit
import Foundation
@testable import SoapWiz

@MainActor
@Suite("Tour launcher")
struct TourLauncherTests {
    private let key = "tour.finished"

    private func makeSUT(
        cloud: FakeFlagStore = FakeFlagStore(),
        local: FakeFlagStore = FakeFlagStore(),
        appearanceTimeout: Duration = .seconds(30),
        isSceneActive: Bool = true
    ) -> TourLauncher {
        TourLauncher(
            progress: TourProgress(
                cloud: cloud,
                local: local,
                notificationCenter: NotificationCenter(),
                timeout: .milliseconds(100),
                account: FakeAccount(.noAccount)
            ),
            appearanceTimeout: appearanceTimeout,
            isSceneActive: isSceneActive
        )
    }

    @Test func presentAtLaunchIfDue_FreshInstall_PresentsFromWelcome() async throws {
        let sut = makeSUT()

        await sut.presentAtLaunchIfDue()

        let presentation = try #require(sut.presentation)
        #expect(presentation.startingPhase == .welcome)
        #expect(presentation.origin == .launch)
        #expect(sut.isPresented)
    }

    @Test func presentAtLaunchIfDue_RelaunchAfterClose_DoesNotPresent() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let first = makeSUT(cloud: cloud, local: local)
        await first.presentAtLaunchIfDue()
        first.close()

        let second = makeSUT(cloud: cloud, local: local)
        await second.presentAtLaunchIfDue()

        #expect(!second.isPresented)
    }

    @Test func presentAtLaunchIfDue_FlagInCloud_DoesNotPresent() async {
        let sut = makeSUT(cloud: FakeFlagStore(finished: true))

        await sut.presentAtLaunchIfDue()

        #expect(!sut.isPresented)
    }

    @Test func close_AtLaunch_MarksFlag() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)
        await sut.presentAtLaunchIfDue()

        sut.close()

        #expect(local.bool(forKey: key))
        #expect(cloud.bool(forKey: key))
        #expect(!sut.isPresented)
    }

    @Test func replay_ThenClose_LeavesUnsetFlagUnset() throws {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)

        sut.replay()
        let presentation = try #require(sut.presentation)
        #expect(presentation.startingPhase == .welcome)
        #expect(presentation.origin == .replay)

        sut.close()

        #expect(!local.bool(forKey: key))
        #expect(!cloud.bool(forKey: key))
        #expect(!sut.isPresented)
    }

    @Test func launchTourEnded_LaunchClose_Increments() async {
        let sut = makeSUT()
        #expect(sut.launchTourEnded == 0)
        await sut.presentAtLaunchIfDue()

        sut.close()

        #expect(sut.launchTourEnded == 1)
    }

    @Test func launchTourEnded_ReplayClose_DoesNotIncrement() {
        let sut = makeSUT()

        sut.replay()
        sut.close()
        sut.replay()
        sut.close()

        #expect(sut.launchTourEnded == 0)
    }

    @Test func presentAtLaunchIfDue_SceneInactive_WaitsForActivation() async throws {
        let sut = makeSUT(isSceneActive: false)

        await sut.presentAtLaunchIfDue()
        #expect(!sut.isPresented)

        sut.sceneActivityChanged(isActive: true)

        let presentation = try #require(sut.presentation)
        #expect(presentation.origin == .launch)
    }

    @Test func sceneActivityChanged_AfterExternalOpenWhilePending_DoesNotPresent() async {
        let sut = makeSUT(isSceneActive: false)
        await sut.presentAtLaunchIfDue()

        sut.noteExternalOpen()
        sut.sceneActivityChanged(isActive: true)

        #expect(!sut.isPresented)
    }

    @Test func presentation_NotConfirmedInTime_ClearsWithoutMarkingFlag() async throws {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local, appearanceTimeout: .milliseconds(20))
        await sut.presentAtLaunchIfDue()
        #expect(sut.isPresented)

        try await Task.sleep(for: .milliseconds(400))

        #expect(!sut.isPresented)
        #expect(!local.bool(forKey: key))
        #expect(!cloud.bool(forKey: key))
        #expect(sut.launchTourEnded == 0)

        sut.replay()
        #expect(sut.isPresented)
    }

    @Test func presentation_ConfirmedInTime_StaysPresented() async throws {
        let sut = makeSUT(appearanceTimeout: .milliseconds(20))
        sut.replay()

        sut.coverDidAppear()
        try await Task.sleep(for: .milliseconds(400))

        #expect(sut.isPresented)
    }

    @Test func presentation_StaleTimerFromClosedPresentation_DoesNotClearNewerOne() async throws {
        let sut = makeSUT(appearanceTimeout: .milliseconds(100))
        sut.replay()
        sut.close()
        sut.replay()
        sut.coverDidAppear()

        try await Task.sleep(for: .milliseconds(500))

        #expect(sut.isPresented)
    }

    @Test func presentAtLaunchIfDue_ReplayAlreadyOpen_UpgradesOriginToLaunch() async throws {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)
        sut.replay()

        await sut.presentAtLaunchIfDue()

        let presentation = try #require(sut.presentation)
        #expect(presentation.origin == .launch)
        #expect(presentation.startingPhase == .welcome)

        sut.close()

        #expect(local.bool(forKey: key))
        #expect(cloud.bool(forKey: key))
        #expect(sut.launchTourEnded == 1)
    }

    @Test func noteExternalOpen_BeforeDecisionCompletes_SuppressesLaunchTourOnly() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)

        sut.noteExternalOpen()
        await sut.presentAtLaunchIfDue()

        #expect(!sut.isPresented)
        #expect(!local.bool(forKey: key))
        #expect(!cloud.bool(forKey: key))

        let nextLaunch = makeSUT(cloud: cloud, local: local)
        await nextLaunch.presentAtLaunchIfDue()
        #expect(nextLaunch.isPresented)
    }

    @Test func presentAtLaunchIfDue_SecondCall_DoesNothing() async {
        let sut = makeSUT()
        await sut.presentAtLaunchIfDue()
        sut.close()

        await sut.presentAtLaunchIfDue()

        #expect(!sut.isPresented)
    }

    @Test func noteExternalOpen_AfterDecision_ClosesTour() async {
        let sut = makeSUT()
        await sut.presentAtLaunchIfDue()
        sut.coverDidAppear()

        sut.noteExternalOpen()

        #expect(sut.presentation == nil)
        #expect(!sut.isPresented)
    }

    @Test func noteExternalOpen_LaunchShowing_LeavesFlagAndEndedCountAlone() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)
        await sut.presentAtLaunchIfDue()

        sut.noteExternalOpen()

        #expect(sut.presentation == nil)
        #expect(!local.bool(forKey: key))
        #expect(!cloud.bool(forKey: key))
        #expect(sut.launchTourEnded == 0)

        let nextLaunch = makeSUT(cloud: cloud, local: local)
        await nextLaunch.presentAtLaunchIfDue()
        #expect(nextLaunch.isPresented)
    }

    @Test func noteExternalOpen_Replay_ClosesWithoutTouchingFlag() {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)
        sut.replay()

        sut.noteExternalOpen()

        #expect(sut.presentation == nil)
        #expect(!local.bool(forKey: key))
        #expect(!cloud.bool(forKey: key))
        #expect(sut.launchTourEnded == 0)
    }

    @Test func noteExternalOpen_Presented_CancelsAppearanceTimer() async throws {
        let sut = makeSUT(appearanceTimeout: .milliseconds(50))
        sut.replay()
        sut.noteExternalOpen()
        sut.replay()
        sut.coverDidAppear()

        try await Task.sleep(for: .milliseconds(300))

        #expect(sut.isPresented)
    }

    @Test func isCoverOnScreen_FollowsAppearAndDismiss() {
        let sut = makeSUT()
        #expect(!sut.isCoverOnScreen)

        sut.coverDidAppear()
        #expect(sut.isCoverOnScreen)

        sut.coverDidDismiss()
        #expect(!sut.isCoverOnScreen)
    }

    @Test func isCoverOnScreen_OutlastsPresentation() {
        let sut = makeSUT()
        sut.replay()
        sut.coverDidAppear()

        sut.noteExternalOpen()

        #expect(!sut.isPresented)
        #expect(sut.isCoverOnScreen)
    }

    @Test func replay_WhileLaunchShowingPending_KeepsLaunchOrigin() async throws {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local)
        await sut.presentAtLaunchIfDue()

        sut.replay()

        let presentation = try #require(sut.presentation)
        #expect(presentation.origin == .launch)

        sut.close()

        #expect(local.bool(forKey: key))
        #expect(cloud.bool(forKey: key))
        #expect(sut.launchTourEnded == 1)
    }
}
