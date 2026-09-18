import Foundation

extension Bundle {
    var appVersionDisplay: String {
        Bundle.appVersionDisplay(
            shortVersion: infoDictionary?["CFBundleShortVersionString"] as? String,
            build: infoDictionary?["CFBundleVersion"] as? String
        )
    }

    static func appVersionDisplay(shortVersion: String?, build: String?) -> String {
        guard let shortVersion else { return "—" }
        guard let build else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }
}
