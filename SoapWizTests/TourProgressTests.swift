import Testing
import Foundation
import CloudKit
@testable import SoapWiz

@Suite("Tour progress")
struct TourProgressTests {
    private let key = "tour.finished"

    private func makeSUT(
        cloud: FakeFlagStore,
        local: FakeFlagStore,
        center: NotificationCenter,
        timeout: Duration,
        account: FakeAccount = FakeAccount(.available)
    ) -> TourProgress {
        TourProgress(cloud: cloud, local: local, notificationCenter: center, timeout: timeout, account: account)
    }

    @Test func shouldPresentAtLaunch_NoAccount_IsTrueWithoutWaiting() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local, center: NotificationCenter(), timeout: .seconds(5), account: FakeAccount(.noAccount))
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start

        #expect(result)
        #expect(cloud.synchronizeCount == 0)
        #expect(elapsed < .seconds(3))
    }

    @Test(arguments: [CKAccountStatus.available, .couldNotDetermine, .temporarilyUnavailable, .restricted])
    func shouldPresentAtLaunch_NoFlagAndAccountNotDefinitelyMissing_WaitsThenPresents(status: CKAccountStatus) async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(
            cloud: cloud,
            local: local,
            center: NotificationCenter(),
            timeout: .milliseconds(300),
            account: FakeAccount(status)
        )
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start

        #expect(result)
        #expect(cloud.synchronizeCount == 1)
        #expect(elapsed >= .milliseconds(200))
        #expect(!local.bool(forKey: key))
    }

    @Test func shouldPresentAtLaunch_SlowAccountCheck_ReturnsWithinTimeout() async {
        let cloud = FakeFlagStore()
        let sut = makeSUT(
            cloud: cloud,
            local: FakeFlagStore(),
            center: NotificationCenter(),
            timeout: .milliseconds(100),
            account: FakeAccount(.noAccount, delay: .seconds(10))
        )
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start

        #expect(result)
        #expect(elapsed < .seconds(5))
    }

    @Test func shouldPresentAtLaunch_LocalFinished_IsFalseWithoutWaiting() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore(finished: true)
        let sut = makeSUT(cloud: cloud, local: local, center: NotificationCenter(), timeout: .seconds(5))

        let result = await sut.shouldPresentAtLaunch()

        #expect(!result)
        #expect(cloud.synchronizeCount == 0)
    }

    @Test func shouldPresentAtLaunch_CloudFinished_IsFalseAndCopiesToLocal() async {
        let cloud = FakeFlagStore(finished: true)
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local, center: NotificationCenter(), timeout: .seconds(5))

        let result = await sut.shouldPresentAtLaunch()

        #expect(!result)
        #expect(local.bool(forKey: key))
        #expect(cloud.synchronizeCount == 0)
    }

    @Test func shouldPresentAtLaunch_FlagArrivesDuringWait_IsFalseBeforeTimeout() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let center = NotificationCenter()
        let sut = makeSUT(cloud: cloud, local: local, center: center, timeout: .seconds(5))
        let key = key

        let poster = Task {
            try? await Task.sleep(for: .milliseconds(50))
            cloud.set(true, forKey: key)
            center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        }
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start
        await poster.value

        #expect(!result)
        #expect(local.bool(forKey: key))
        #expect(elapsed < .seconds(3))
    }

    @Test func shouldPresentAtLaunch_NotificationButCloudStillFalse_KeepsWaitingThenPresents() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let center = NotificationCenter()
        let sut = makeSUT(cloud: cloud, local: local, center: center, timeout: .milliseconds(300))

        let poster = Task {
            try? await Task.sleep(for: .milliseconds(50))
            center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        }
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start
        await poster.value

        #expect(result)
        #expect(!local.bool(forKey: key))
        #expect(elapsed >= .milliseconds(200))
    }

    @Test func shouldPresentAtLaunch_UnrelatedChangeThenFlag_IsFalseBeforeTimeout() async {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let center = NotificationCenter()
        let sut = makeSUT(cloud: cloud, local: local, center: center, timeout: .seconds(5))
        let key = key

        let poster = Task {
            try? await Task.sleep(for: .milliseconds(50))
            center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
            try? await Task.sleep(for: .milliseconds(50))
            cloud.set(true, forKey: key)
            center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        }
        let clock = ContinuousClock()
        let start = clock.now

        let result = await sut.shouldPresentAtLaunch()
        let elapsed = clock.now - start
        await poster.value

        #expect(!result)
        #expect(local.bool(forKey: key))
        #expect(elapsed < .seconds(3))
    }

    @Test func markFinished_WritesBothStoresAndSynchronizesCloudOnce() {
        let cloud = FakeFlagStore()
        let local = FakeFlagStore()
        let sut = makeSUT(cloud: cloud, local: local, center: NotificationCenter(), timeout: .milliseconds(20))

        sut.markFinished()

        #expect(cloud.bool(forKey: key))
        #expect(local.bool(forKey: key))
        #expect(cloud.synchronizeCount == 1)
    }

    @Test(arguments: [(false, false, false), (true, false, true), (false, true, true), (true, true, true)])
    func isFinished_EitherStoreFinished_IsTrue(cloudFinished: Bool, localFinished: Bool, expected: Bool) {
        let sut = makeSUT(
            cloud: FakeFlagStore(finished: cloudFinished),
            local: FakeFlagStore(finished: localFinished),
            center: NotificationCenter(),
            timeout: .milliseconds(20)
        )

        #expect(sut.isFinished == expected)
    }
}

private struct FakeAccount: SyncAccountStatusProviding {
    let status: CKAccountStatus
    let delay: Duration?

    init(_ status: CKAccountStatus, delay: Duration? = nil) {
        self.status = status
        self.delay = delay
    }

    func accountStatus() async -> CKAccountStatus {
        if let delay { try? await Task.sleep(for: delay) }
        return status
    }
}

/// Reached from the poster task and the code under test, so reads and writes
/// go through a lock.
private final class FakeFlagStore: TourFlagStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Bool] = [:]
    private var synchronizeCalls = 0

    init(finished: Bool = false) {
        if finished { values["tour.finished"] = true }
    }

    var synchronizeCount: Int {
        lock.withLock { synchronizeCalls }
    }

    func bool(forKey key: String) -> Bool {
        lock.withLock { values[key] ?? false }
    }

    func set(_ value: Bool, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    func synchronize() -> Bool {
        lock.withLock { synchronizeCalls += 1 }
        return true
    }
}
