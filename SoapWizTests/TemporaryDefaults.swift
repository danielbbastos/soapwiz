import Foundation
import Testing

/// Call `remove()` explicitly; a `deinit` could fire right after the last use and wipe the store mid-test.
nonisolated final class TemporaryDefaults: @unchecked Sendable {
    private static let runStart = Date()
    private static let preferencesDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Preferences")

    let suiteName: String
    let defaults: UserDefaults

    var plistURL: URL { Self.preferencesDirectory.appendingPathComponent("\(suiteName).plist") }

    init(prefix: String) throws {
        Self.sweepStale(prefix: prefix, in: Self.preferencesDirectory, before: Self.runStart)
        suiteName = "\(prefix).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// Empties the domain and deletes its plist, though `cfprefsd` can still rewrite an empty file; `sweepStale` clears those next run.
    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// `cfprefsd` can rewrite an emptied plist after `remove()` deleted it, so earlier runs' strays are swept here.
    static func sweepStale(prefix: String, in directory: URL, before cutoff: Date) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(prefix).") && file.pathExtension == "plist" {
            let modified = try? file.resourceValues(forKeys: Set(keys)).contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
