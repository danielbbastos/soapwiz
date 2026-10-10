import Foundation
import Testing

@Suite("Temporary defaults")
struct TemporaryDefaultsTests {

    @Test func remove_AfterWriting_ClearsTheValue() throws {
        let temp = try TemporaryDefaults(prefix: "TemporaryDefaultsTests")
        temp.defaults.set("value", forKey: "key")

        temp.remove()

        let reopened = try #require(UserDefaults(suiteName: temp.suiteName))
        #expect(reopened.string(forKey: "key") == nil)
        temp.remove()
    }

    @Test func remove_CalledTwice_StillClearsTheValue() throws {
        let temp = try TemporaryDefaults(prefix: "TemporaryDefaultsTests")
        temp.defaults.set("value", forKey: "key")

        temp.remove()
        temp.remove()

        let reopened = try #require(UserDefaults(suiteName: temp.suiteName))
        #expect(reopened.string(forKey: "key") == nil)
        temp.remove()
    }

    @Test func sweepStale_OldAndFreshFiles_DeletesOnlyOldOnesWithThePrefix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryDefaultsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("SweepTests.old.plist")
        let fresh = directory.appendingPathComponent("SweepTests.fresh.plist")
        let otherPrefix = directory.appendingPathComponent("OtherTests.old.plist")
        for file in [old, fresh, otherPrefix] {
            try Data().write(to: file)
        }
        let cutoff = Date()
        let past = try #require(Calendar.current.date(byAdding: .hour, value: -1, to: cutoff))
        let future = try #require(Calendar.current.date(byAdding: .hour, value: 1, to: cutoff))
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: otherPrefix.path)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: fresh.path)

        TemporaryDefaults.sweepStale(prefix: "SweepTests", in: directory, before: cutoff)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: otherPrefix.path))
    }

    @Test func init_SamePrefix_GetsDistinctSuiteNames() throws {
        let first = try TemporaryDefaults(prefix: "TemporaryDefaultsTests")
        let second = try TemporaryDefaults(prefix: "TemporaryDefaultsTests")
        defer {
            first.remove()
            second.remove()
        }

        #expect(first.suiteName != second.suiteName)
    }
}
