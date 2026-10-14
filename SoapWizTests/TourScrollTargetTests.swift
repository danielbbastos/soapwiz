import Testing
@testable import SoapWiz

/// Which phase and device each of the tour's form scrolls applies to.
@Suite("Tour scroll targets")
@MainActor
struct TourScrollTargetTests {

    @Test func oilsCard_AppliesToBasicsOnAPhoneOnly() {
        #expect(TourScrollTarget.oilsCard.applies(to: .step(.basics), isPad: false))
        #expect(!TourScrollTarget.oilsCard.applies(to: .step(.basics), isPad: true))
    }

    @Test func cureSection_AppliesToBatchOnPhoneAndPad() {
        #expect(TourScrollTarget.cureSection.applies(to: .step(.batch), isPad: false))
        #expect(TourScrollTarget.cureSection.applies(to: .step(.batch), isPad: true))
    }

    @Test func targets_DoNotApplyToOtherPhases() {
        #expect(!TourScrollTarget.oilsCard.applies(to: .step(.batch), isPad: false))
        #expect(!TourScrollTarget.cureSection.applies(to: .step(.basics), isPad: false))
        #expect(!TourScrollTarget.cureSection.applies(to: .welcome, isPad: false))
        #expect(!TourScrollTarget.cureSection.applies(to: .finish, isPad: true))
    }
}
