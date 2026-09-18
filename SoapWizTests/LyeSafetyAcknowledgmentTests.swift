import Testing
import Foundation
@testable import SoapWiz

@Suite("Lye safety acknowledgment")
final class LyeSafetyAcknowledgmentTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let sut: LyeSafetyAcknowledgment

    init() throws {
        suiteName = "LyeSafetyAcknowledgmentTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        sut = LyeSafetyAcknowledgment(defaults: defaults)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func isAcknowledged_FreshInstall_IsFalse() {
        #expect(!sut.isAcknowledged)
    }

    @Test func shouldPresent_SoapRecipeNotAcknowledged_IsTrue() {
        #expect(sut.shouldPresent(makesSoap: true))
    }

    @Test func shouldPresent_SoapRecipeAcknowledged_IsFalse() {
        sut.acknowledge()

        #expect(!sut.shouldPresent(makesSoap: true))
    }

    @Test(arguments: [false, true])
    func shouldPresent_NonSoapRecipe_IsNeverTrue(_ acknowledged: Bool) {
        if acknowledged { sut.acknowledge() }

        #expect(!sut.shouldPresent(makesSoap: false))
    }

    /// A relaunch reads the same defaults through a new instance.
    @Test func acknowledge_SurvivesANewInstance() {
        sut.acknowledge()

        let relaunched = LyeSafetyAcknowledgment(defaults: defaults)

        #expect(relaunched.isAcknowledged)
        #expect(!relaunched.shouldPresent(makesSoap: true))
    }

    @Test func acknowledge_OtherDefaults_AreUnaffected() throws {
        sut.acknowledge()

        let otherSuite = "LyeSafetyAcknowledgmentTests.\(UUID().uuidString)"
        let other = LyeSafetyAcknowledgment(defaults: try #require(UserDefaults(suiteName: otherSuite)))

        #expect(!other.isAcknowledged)
        UserDefaults().removePersistentDomain(forName: otherSuite)
    }
}
