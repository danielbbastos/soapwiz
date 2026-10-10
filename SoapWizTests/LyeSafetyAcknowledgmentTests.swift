import Testing
import Foundation
@testable import SoapWiz

@Suite("Lye safety acknowledgment")
final class LyeSafetyAcknowledgmentTests {
    private let temp: TemporaryDefaults
    private let sut: LyeSafetyAcknowledgment
    private var defaults: UserDefaults { temp.defaults }

    init() throws {
        temp = try TemporaryDefaults(prefix: "LyeSafetyAcknowledgmentTests")
        sut = LyeSafetyAcknowledgment(defaults: temp.defaults)
    }

    deinit {
        temp.remove()
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

    @Test func reset_AfterAcknowledging_AsksAgain() {
        sut.acknowledge()

        sut.reset()

        #expect(!sut.isAcknowledged)
        #expect(sut.shouldPresent(makesSoap: true))
    }

    @Test func acknowledge_OtherDefaults_AreUnaffected() throws {
        sut.acknowledge()

        let otherDefaults = try TemporaryDefaults(prefix: "LyeSafetyAcknowledgmentTests")
        defer { otherDefaults.remove() }
        let other = LyeSafetyAcknowledgment(defaults: otherDefaults.defaults)

        #expect(!other.isAcknowledged)
    }
}
