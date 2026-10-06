import Testing
import Foundation
@testable import SoapWiz

@Suite("Sync preference")
final class SyncPreferenceTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let sut: SyncPreference

    init() throws {
        suiteName = "SyncPreferenceTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        sut = SyncPreference(defaults: defaults)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func usesOffline_FreshInstall_IsFalse() {
        #expect(!sut.usesOffline)
    }

    /// The next launch reads the same defaults through a new instance.
    @Test func usesOffline_TurnedOn_SurvivesANewInstance() {
        sut.usesOffline = true

        #expect(SyncPreference(defaults: defaults).usesOffline)
    }

    @Test func usesOffline_TurnedBackOff_IsFalse() {
        sut.usesOffline = true

        sut.usesOffline = false

        #expect(!sut.usesOffline)
    }
}
