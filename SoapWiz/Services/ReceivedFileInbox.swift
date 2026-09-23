import Foundation
import OSLog

/// Where iOS puts a file another app hands to SoapWiz.
///
/// `LSSupportsOpeningDocumentsInPlace` is `NO`, so a `.soapwizrecipe` opened from
/// Mail, Messages or Files arrives as a copy in `Documents/Inbox` rather than as
/// the sender's original. iOS never deletes those copies, and the recipe is in
/// the store once imported, so the copy is removed after it has been read.
enum ReceivedFileInbox {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "import")

    static var directory: URL {
        URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Deletes `url` if it is one of the copies iOS made, and leaves anything
    /// else alone — a file picked in-app is the user's original.
    static func removeIfReceived(_ url: URL, inbox: URL = directory) {
        guard contains(url, in: inbox) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            log.error("Couldn't remove a received file: \(error, privacy: .public)")
        }
    }

    static func contains(_ url: URL, in inbox: URL) -> Bool {
        guard url.isFileURL else { return false }
        let file = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let folder = inbox.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return file.count > folder.count && file.starts(with: folder)
    }
}
