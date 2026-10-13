import CloudKit
import Foundation

/// The slice of a key-value store the tour flag needs, so tests can stand in
/// for iCloud and for `UserDefaults`.
nonisolated protocol TourFlagStore: Sendable {
    func bool(forKey: String) -> Bool
    func set(_ value: Bool, forKey: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: nonisolated TourFlagStore {}
extension UserDefaults: nonisolated TourFlagStore {}

/// Whether the user has finished the first-launch tour, shared across their
/// devices through the iCloud key-value store.
///
/// Skipping counts as finishing, so callers call `markFinished()` on Skip as
/// well as on the last step. Replaying the tour from Settings never resets the
/// flag: a replay is a choice, and the next launch shouldn't repeat it.
///
/// The flag lives in `UserDefaults` too. A device that already knows the answer
/// launches without waiting on iCloud, and an offline device remembers a tour
/// it finished.
///
/// `nonisolated` for the same reason as `LyeSafetyAcknowledgment`: a typed view
/// over key-value stores, constructible from a default argument.
nonisolated struct TourProgress {
    private enum Key {
        static let finished = "tour.finished"
    }

    private let cloud: any TourFlagStore
    private let local: any TourFlagStore
    private let notificationCenter: NotificationCenter
    private let timeout: Duration
    private let account: (any SyncAccountStatusProviding)?

    /// `account` is optional because the production default names a
    /// main-actor constant, which a default argument can't reach from here; it
    /// is resolved when the launch decision runs.
    init(
        cloud: any TourFlagStore = NSUbiquitousKeyValueStore.default,
        local: any TourFlagStore = UserDefaults.standard,
        notificationCenter: NotificationCenter = .default,
        timeout: Duration = .seconds(2),
        account: (any SyncAccountStatusProviding)? = nil
    ) {
        self.cloud = cloud
        self.local = local
        self.notificationCenter = notificationCenter
        self.timeout = timeout
        self.account = account
    }

    var isFinished: Bool {
        local.bool(forKey: Key.finished) || cloud.bool(forKey: Key.finished)
    }

    func markFinished() {
        local.set(true, forKey: Key.finished)
        cloud.set(true, forKey: Key.finished)
        cloud.synchronize()
    }

    /// Whether to show the tour on this launch.
    ///
    /// A fresh install on a second device would otherwise replay a tour the
    /// user finished elsewhere, because iCloud hasn't delivered the flag yet.
    /// So when neither store knows, wait briefly for it, ending early once the
    /// flag arrives, and show the tour only if it still hasn't arrived.
    /// With no iCloud account nothing can arrive, so a new user doesn't wait.
    /// The account check counts toward the same timeout as the wait.
    func shouldPresentAtLaunch() async -> Bool {
        if local.bool(forKey: Key.finished) { return false }
        if adoptCloudFlag() { return false }

        await waitForCloudChange()

        return !adoptCloudFlag()
    }

    /// Copies a finished flag from iCloud to this device.
    private func adoptCloudFlag() -> Bool {
        guard cloud.bool(forKey: Key.finished) else { return false }
        local.set(true, forKey: Key.finished)
        return true
    }

    /// Observes before synchronizing, so a change delivered by the
    /// synchronization itself can't slip past. Only a notification that leaves
    /// the flag set ends the wait: iCloud reports changes to any key, and
    /// another key can arrive first.
    private func waitForCloudChange() async {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let cloud = cloud
        let observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: nil
        ) { _ in
            if cloud.bool(forKey: Key.finished) {
                continuation.yield()
            }
        }
        defer { notificationCenter.removeObserver(observer) }

        let clock = ContinuousClock()
        let start = clock.now
        let account = account

        // Only a definite "no account" skips the wait: any other answer, or no
        // answer in time, leaves open that the flag is on its way.
        let status = await Self.race(timeoutAfter: timeout, fallback: CKAccountStatus.couldNotDetermine) {
            if let account { return await account.accountStatus() }
            let containerIdentifier = await ModelContainerFactory.cloudKitContainerIdentifier
            return await CloudKitAccountStatusProvider(containerIdentifier: containerIdentifier).accountStatus()
        }
        if status == .noAccount { return }

        let remaining = timeout - (clock.now - start)
        guard remaining > .zero else { return }

        cloud.synchronize()

        await Self.race(timeoutAfter: remaining, fallback: ()) {
            for await _ in changes { return }
        }
    }

    /// Returns whichever finishes first, `operation` or the timeout.
    ///
    /// Unstructured tasks rather than a task group: a group waits for every
    /// child, and an account check that ignores cancellation would hold the
    /// launch past the timeout.
    private static func race<Value: Sendable>(
        timeoutAfter duration: Duration,
        fallback: Value,
        operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        let (results, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingOldest(1))
        let work = Task {
            continuation.yield(await operation())
        }
        let timer = Task {
            try? await Task.sleep(for: duration)
            continuation.yield(fallback)
        }
        defer {
            work.cancel()
            timer.cancel()
        }
        for await result in results { return result }
        return fallback
    }
}
