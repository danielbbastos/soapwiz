import Foundation

/// Lines the import progress screen steps through, a few seconds apart, while
/// the model has read nothing yet. The first stretch of a read can take several
/// seconds, and a status line that never changes reads as a hang.
@MainActor
@Observable
final class RecipeImportWaitHints {
    static let lines = [
        "This might take some time\u{2026}",
        "Still reading, longer recipes take a while\u{2026}",
        "The recipe is read on this device, so it can be slow\u{2026}",
        "Hang on, the ingredients are on their way\u{2026}"
    ]

    private var index: Int?

    /// Waits between one line and the next. Injected so tests can step through
    /// the lines without waiting on a real clock.
    @ObservationIgnored
    private let pause: () async throws -> Void

    @ObservationIgnored
    private var task: Task<Void, Never>?

    /// The line to show, or `nil` until the first pause has elapsed and again
    /// once stopped.
    var current: String? { index.map { Self.lines[$0] } }

    nonisolated init(pause: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(5)) }) {
        self.pause = pause
    }

    /// Steps through `lines` until stopped, wrapping round.
    func start() {
        stop()
        let pause = pause
        task = Task { [weak self] in
            while (try? await pause()) != nil, !Task.isCancelled {
                guard let self else { return }
                index = index.map { ($0 + 1) % Self.lines.count } ?? 0
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        index = nil
    }
}
