import Testing
import CloudKit
import Foundation
@testable import SoapWiz

@MainActor
@Suite("Tour launcher")
struct TourLauncherTests {
    private let key = "tour.finished"

    private func makeSUT(cloud: FakeFlagStore = FakeFlagStore(), local: FakeFlagStore = FakeFlagStore()) -> TourLauncher {
        TourLauncher(progress: TourProgress(
            cloud: cloud,
            local: local,
            notificationCenter: NotificationCenter(),
            timeout: .milliseconds(100),
            account: FakeAccount(.noAccount)
        ))
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

    @Test func tourEnded_EveryClose_Increments() {
        let sut = makeSUT()
        #expect(sut.tourEnded == 0)

        sut.replay()
        sut.close()
        sut.replay()
        sut.close()

        #expect(sut.tourEnded == 2)
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

    @Test func noteExternalOpen_AfterDecision_KeepsTourOpen() async {
        let sut = makeSUT()
        await sut.presentAtLaunchIfDue()

        sut.noteExternalOpen()

        #expect(sut.isPresented)
    }
}
