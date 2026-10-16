import OSLog

enum Signposts {
    /// Shows up on Instruments' Points of Interest track, for profiling what runs when the app returns to the foreground.
    static let foreground = OSSignposter(subsystem: "pt.tachyon.SoapWiz", category: .pointsOfInterest)

    /// Shows up on Instruments' Points of Interest track, for timing the onboarding tour's start-up:
    /// the sandbox build and the first step appearing.
    static let tour = OSSignposter(subsystem: "pt.tachyon.SoapWiz", category: .pointsOfInterest)

    /// Shows up on Instruments' Points of Interest track, for measuring how long a fresh install
    /// waits on StoreKit before it can pick a store.
    static let entitlement = OSSignposter(subsystem: "pt.tachyon.SoapWiz", category: .pointsOfInterest)
}
