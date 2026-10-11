import OSLog

enum Signposts {
    /// Shows up on Instruments' Points of Interest track, for profiling what runs when the app returns to the foreground.
    static let foreground = OSSignposter(subsystem: "pt.tachyon.SoapWiz", category: .pointsOfInterest)
}
