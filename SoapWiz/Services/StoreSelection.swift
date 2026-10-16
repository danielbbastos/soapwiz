import Foundation

/// Decides which store a launch opens: the CloudKit-mirrored one is for Pro
/// users who haven't turned sync off, everyone else gets the local one.
///
/// Kept apart from `StoreHost` so every branch can be tested without opening a
/// container. The store is opened once per launch, so the answer has to be
/// right before the first view is built.
enum StoreSelection {
    /// How long a fresh install waits for StoreKit before opening the local
    /// store. A wrong guess costs little: a Pro user who misses the window is
    /// local for one launch and mirrored the next.
    nonisolated static let entitlementTimeout: Duration = .seconds(1)

    static func isOffline(isPro: Bool, prefersOffline: Bool) -> Bool {
        localCause(isPro: isPro, prefersOffline: prefersOffline) != nil
    }

    /// `nil` when the launch mirrors. Pro wins over the toggle as the reason:
    /// a free user who also switched sync off still can't turn it on without
    /// buying, so that is the fact worth showing.
    static func localCause(
        isPro: Bool,
        prefersOffline: Bool
    ) -> ModelContainerFactory.LocalStoreCause? {
        if !isPro { return .requiresPro }
        return prefersOffline ? .offlineByChoice : nil
    }

    /// Only a device StoreKit has never answered on has nothing to go by. Any
    /// other launch trusts the last answer and opens the store without waiting.
    static func needsEntitlementWait(hint: Bool?) -> Bool {
        hint == nil
    }

    /// A fresh answer beats the remembered one; with neither, the launch is
    /// treated as free, the safe side since it never touches iCloud.
    static func launchIsPro(answer: Bool?, hint: Bool?) -> Bool {
        answer ?? hint ?? false
    }

    /// Returns what `read` answers, or `nil` if `timeout` passes first.
    ///
    /// The caller resumes the moment either finishes and never awaits the
    /// other. A task group would wait for its slower child on the way out, so a
    /// read that ignores cancellation would hold the launch for as long as it
    /// likes. The loser is cancelled as a courtesy, not waited for.
    static func answer(
        within timeout: Duration,
        read: @escaping @MainActor () async -> Bool
    ) async -> Bool? {
        await withCheckedContinuation { continuation in
            let race = EntitlementRace(continuation)
            race.reader = Task { @MainActor in
                race.finish(await read())
            }
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                race.finish(nil)
            }
        }
    }
}

/// Resumes its continuation once, for whichever of the read and the clock
/// finishes first, and ignores the other.
@MainActor
private final class EntitlementRace {
    private var continuation: CheckedContinuation<Bool?, Never>?
    var reader: Task<Void, Never>?
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Bool?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
        reader?.cancel()
        timer?.cancel()
    }
}
