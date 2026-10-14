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

    /// Upgraded to `.launch` when the launch decision comes back due while a
    /// replay is already up, so closing that showing still counts as the first.
    var origin: TourOrigin
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

    /// Bumped when the first-launch showing closes, so the real app can switch
    /// to its first tab once the tour is gone without the launcher knowing
    /// about navigation. A replay leaves the app where the user was.
    private(set) var launchTourEnded = 0

    private let progress: TourProgress
    private let appearanceTimeout: Duration
    private var hasDecidedAtLaunch = false
    private var hasStartedLaunchDecision = false
    private var externalOpenNoted = false
    private var isSceneActive: Bool
    private var launchPending = false

    /// Tells a timer which showing it was started for, so one that outlives its
    /// presentation can't clear a later one.
    private var presentationID = 0
    private var appearanceTask: Task<Void, Never>?

    /// True from the cover reaching the screen until it has finished leaving,
    /// which outlasts `presentation`: the presentation clears as the cover starts
    /// to go, and a sheet requested in that window is dropped.
    private(set) var isCoverOnScreen = false

    var isPresented: Bool { presentation != nil }

    /// `isSceneActive` starts false in the app, which reports the real phase as
    /// soon as the root appears.
    init(
        progress: TourProgress = TourProgress(),
        appearanceTimeout: Duration = .seconds(3),
        isSceneActive: Bool = true
    ) {
        self.progress = progress
        self.appearanceTimeout = appearanceTimeout
        self.isSceneActive = isSceneActive
    }

    /// Runs at most once per launcher: the app root rebuilds `ContentView` after
    /// an "Erase everything" reset, and the tour shouldn't come back with it.
    func presentAtLaunchIfDue() async {
        guard !hasStartedLaunchDecision else { return }
        hasStartedLaunchDecision = true

        let due = await progress.shouldPresentAtLaunch()
        hasDecidedAtLaunch = true

        guard due, !externalOpenNoted else { return }
        presentLaunchIfPossible()
    }

    /// SwiftUI can't present a cover while the app isn't active, so a launch
    /// decision that lands early waits here rather than leaving a presentation
    /// that never appears.
    func sceneActivityChanged(isActive: Bool) {
        isSceneActive = isActive
        guard isActive, launchPending, !externalOpenNoted else { return }
        presentLaunchIfPossible()
    }

    /// A replay that lands on a first-launch showing still waiting to appear
    /// keeps its origin, mirroring `presentLaunchIfPossible`: closing it must
    /// still count as the first showing, or the tour comes back next launch.
    func replay() {
        let origin: TourOrigin = presentation?.origin == .launch ? .launch : .replay
        show(TourPresentation(startingPhase: .welcome, origin: origin))
    }

    /// The cover reports that it reached the screen. Without it the
    /// presentation is dropped after the timeout.
    func coverDidAppear() {
        isCoverOnScreen = true
        cancelAppearanceTimer()
    }

    /// The cover's `onDismiss`, once it is fully off screen.
    func coverDidDismiss() {
        isCoverOnScreen = false
    }

    /// Skipping, finishing and a sandbox that failed to build all mark the flag:
    /// a broken sandbox shouldn't flash the cover on every launch, and Settings
    /// can still replay the tour.
    func close() {
        cancelAppearanceTimer()
        let wasLaunch = presentation?.origin == .launch
        if wasLaunch {
            progress.markFinished()
        }
        presentation = nil
        if wasLaunch {
            launchTourEnded += 1
        }
    }

    /// A recipe file opening the app shows an import review, and possibly the
    /// lye notice, which must not stack with the cover. A tour already up is
    /// closed and one still due is dropped, for this launch only: the flag stays
    /// unset, so the tour shows next launch. Nor does it count as an ended
    /// launch tour, which would send the app to Inventory when the import needs
    /// Recipes.
    func noteExternalOpen() {
        if presentation != nil {
            cancelAppearanceTimer()
            presentation = nil
        }
        if launchPending {
            launchPending = false
            return
        }
        guard !hasDecidedAtLaunch else { return }
        externalOpenNoted = true
    }

    #if DEBUG
    func presentForDebug(at phase: TourPhase) {
        show(TourPresentation(startingPhase: phase, origin: .debug))
    }
    #endif

    private func presentLaunchIfPossible() {
        if presentation != nil {
            launchPending = false
            presentation?.origin = .launch
            return
        }
        guard isSceneActive else {
            launchPending = true
            return
        }
        launchPending = false
        show(TourPresentation(startingPhase: .welcome, origin: .launch))
    }

    private func cancelAppearanceTimer() {
        appearanceTask?.cancel()
        appearanceTask = nil
    }

    /// A presentation the cover never confirms is cleared without marking the
    /// flag or counting as an ended tour: the user never saw it.
    private func show(_ newPresentation: TourPresentation) {
        appearanceTask?.cancel()
        presentationID += 1
        let id = presentationID
        presentation = newPresentation
        appearanceTask = Task {
            try? await Task.sleep(for: appearanceTimeout)
            guard !Task.isCancelled, presentationID == id else { return }
            presentation = nil
            appearanceTask = nil
        }
    }
}
