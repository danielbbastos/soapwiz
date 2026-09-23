import Testing
import Foundation
@testable import SoapWiz

@Suite
struct ReceivedFileInboxTests {

    private let root: URL
    private let inbox: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ReceivedFileInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        inbox = root.appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    private func file(named name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try Data("{}".utf8).write(to: url)
        return url
    }

    @Test func removeIfReceived_FileInInbox_DeletesIt() throws {
        let received = try file(named: "Recipe.soapwizrecipe", in: inbox)

        ReceivedFileInbox.removeIfReceived(received, inbox: inbox)

        #expect(!FileManager.default.fileExists(atPath: received.path(percentEncoded: false)))
    }

    @Test func removeIfReceived_FileOutsideInbox_LeavesIt() throws {
        let picked = try file(named: "Recipe.soapwizrecipe", in: root)

        ReceivedFileInbox.removeIfReceived(picked, inbox: inbox)

        #expect(FileManager.default.fileExists(atPath: picked.path(percentEncoded: false)))
    }

    @Test func removeIfReceived_SiblingFolderSharingThePrefix_LeavesIt() throws {
        let sibling = root.appending(path: "InboxBackup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let picked = try file(named: "Recipe.soapwizrecipe", in: sibling)

        ReceivedFileInbox.removeIfReceived(picked, inbox: inbox)

        #expect(FileManager.default.fileExists(atPath: picked.path(percentEncoded: false)))
    }

    @Test func removeIfReceived_MissingFile_DoesNothing() {
        let missing = inbox.appending(path: "Gone.soapwizrecipe")

        ReceivedFileInbox.removeIfReceived(missing, inbox: inbox)

        #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
    }

    @Test func contains_TheInboxFolderItself_IsFalse() {
        #expect(!ReceivedFileInbox.contains(inbox, in: inbox))
    }

    @Test func contains_NonFileURL_IsFalse() throws {
        let web = try #require(URL(string: "https://example.com/Inbox/Recipe.soapwizrecipe"))

        #expect(!ReceivedFileInbox.contains(web, in: inbox))
    }
}
