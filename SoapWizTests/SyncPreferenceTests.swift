import Testing
import Foundation
@testable import SoapWiz

@Suite("Sync preference")
final class SyncPreferenceTests {
    private let temp: TemporaryDefaults
    private let sut: SyncPreference
    private var defaults: UserDefaults { temp.defaults }

    init() throws {
        temp = try TemporaryDefaults(prefix: "SyncPreferenceTests")
        sut = SyncPreference(defaults: temp.defaults)
    }

    deinit {
        temp.remove()
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
