import Observation

/// Where a presentation of the tour came from, which decides whether closing it
/// counts toward the "seen it" flag.
enum TourOrigin {
    case launch
    case replay
    #if DEBUG
    case debug
    #endif
}

/// One showing of the tour.
struct TourPresentation {
    let startingPhase: TourPhase
    let origin: TourOrigin
}

/// Decides when the onboarding tour is on screen: once at first launch, again
/// whenever the user replays it from Settings.
///
/// Only the first-launch showing touches the finished flag. A replay is a
/// choice, and neither finishing nor skipping it changes what the next launch
/// does.
@Observable
final class TourLauncher {
    private(set) var presentation: TourPresentation?

    /// Bumped on every close, so the real app can switch to its first tab once
    /// the tour is gone without the launcher knowing about navigation.
    private(set) var tourEnded = 0

    private let progress: TourProgress
    private var hasDecidedAtLaunch = false
    private var hasStartedLaunchDecision = false
    private var externalOpenNoted = false

    var isPresented: Bool { presentation != nil }

    init(progress: TourProgress = TourProgress()) {
        self.progress = progress
    }

    /// Runs at most once per launcher: the app root rebuilds `ContentView` after
    /// an "Erase everything" reset, and the tour shouldn't come back with it.
    func presentAtLaunchIfDue() async {
        guard !hasStartedLaunchDecision else { return }
        hasStartedLaunchDecision = true

        let due = await progress.shouldPresentAtLaunch()
        hasDecidedAtLaunch = true

        guard due, !externalOpenNoted, presentation == nil else { return }
        presentation = TourPresentation(startingPhase: .welcome, origin: .launch)
    }

    func replay() {
        presentation = TourPresentation(startingPhase: .welcome, origin: .replay)
    }

    /// Skipping, finishing and a sandbox that failed to build all mark the flag:
    /// a broken sandbox shouldn't flash the cover on every launch, and Settings
    /// can still replay the tour.
    func close() {
        if presentation?.origin == .launch {
            progress.markFinished()
        }
        presentation = nil
        tourEnded += 1
    }

    /// A recipe file opening the app shows an import review, and possibly the
    /// lye notice, which must not stack with the cover. Dropped for this launch
    /// only: the flag stays unset, so the tour shows next launch.
    func noteExternalOpen() {
        guard !hasDecidedAtLaunch else { return }
        externalOpenNoted = true
    }

    #if DEBUG
    func presentForDebug(at phase: TourPhase) {
        presentation = TourPresentation(startingPhase: phase, origin: .debug)
    }
    #endif
}
