import OSLog
import SwiftData
import SwiftUI

/// The onboarding tour: the real tab interface running on a `TourSandbox`'s
/// in-memory store, with the guide's overlay on top. Presented full screen from
/// outside `ContentView`, so nothing the tour does can reach the app's own
/// navigation, and the sandbox is built when it opens and gone when it closes.
///
/// `onClose` hears whether the tour was finished (true) or skipped, or could
/// not be built (false).
struct TourCover: View {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "tour")

    /// The real settings' currency, so the sample's costs read in the user's own.
    let currencyCode: String
    let startingPhase: TourPhase
    let onClose: (_ finished: Bool) -> Void

    @State private var session: TourSession?

    init(
        currencyCode: String,
        startingPhase: TourPhase = .welcome,
        onClose: @escaping (_ finished: Bool) -> Void
    ) {
        self.currencyCode = currencyCode
        self.startingPhase = startingPhase
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let session {
                ContentView(navigation: session.sandbox.navigation)
                    .modelContainer(session.sandbox.container)
                    .environment(session.sandbox.inventoryRows)
                    .environment(session.sandbox.settings)
                    .environment(session.sandbox.syncHealth)
                    .environment(\.isTourSandbox, true)
                    .environment(\.tourGuide, session.guide)
                    // Once the interface is up, so the first step's controls
                    // can report where they are.
                    .task { session.guide.start(at: startingPhase) }
            } else {
                Color.clear.ledgerBackground()
            }
        }
        .task { build() }
    }

    private func build() {
        guard session == nil else { return }
        let interval = Signposts.tour.beginInterval("Tour sandbox build")
        defer { Signposts.tour.endInterval("Tour sandbox build", interval) }
        do {
            let sandbox = try TourSandbox(currencyCode: currencyCode)
            let guide = TourGuide(
                navigation: sandbox.navigation,
                context: sandbox.container.mainContext,
                phase: startingPhase,
                onClose: onClose
            )
            session = TourSession(sandbox: sandbox, guide: guide)
        } catch {
            Self.log.error("Building the tour sandbox failed: \(error, privacy: .public)")
            onClose(false)
        }
    }
}

/// A sandbox and the guide driving it, kept together for as long as the cover
/// is up.
private struct TourSession {
    let sandbox: TourSandbox
    let guide: TourGuide
}

#if DEBUG
extension TourPhase {
    /// The phase named by the launch argument `-SoapWizTourStep N`, for
    /// screenshots: 0 is the welcome card, 1 to 10 the steps, 11 the closing
    /// card. Nil when the argument is absent or out of range.
    static var launchArgument: TourPhase? {
        guard let text = UserDefaults.standard.string(forKey: "SoapWizTourStep"),
              let position = Int(text),
              (0...TourPhase.lastPosition).contains(position) else { return nil }
        return TourPhase(position: position)
    }
}
#endif
