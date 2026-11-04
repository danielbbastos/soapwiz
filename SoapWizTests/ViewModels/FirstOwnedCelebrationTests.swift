import Testing
@testable import SoapWiz

@Suite("FirstOwnedCelebration")
struct FirstOwnedCelebrationTests {

    @Test func shouldPlay_FirstOwnedWhileTracking_Plays() {
        #expect(FirstOwnedCelebration.shouldPlay(old: 0, new: 1, tracksInventory: true, alreadyCelebrated: false))
    }

    @Test func shouldPlay_AlreadyCelebrated_DoesNotPlay() {
        #expect(!FirstOwnedCelebration.shouldPlay(old: 0, new: 1, tracksInventory: true, alreadyCelebrated: true))
    }

    @Test func shouldPlay_TrackingOff_DoesNotPlay() {
        #expect(!FirstOwnedCelebration.shouldPlay(old: 0, new: 1, tracksInventory: false, alreadyCelebrated: false))
    }

    @Test func shouldPlay_NotFromZero_DoesNotPlay() {
        #expect(!FirstOwnedCelebration.shouldPlay(old: 1, new: 2, tracksInventory: true, alreadyCelebrated: false))
        #expect(!FirstOwnedCelebration.shouldPlay(old: -1, new: 1, tracksInventory: true, alreadyCelebrated: false))
    }

    @Test func shouldPlay_NotToOne_DoesNotPlay() {
        #expect(!FirstOwnedCelebration.shouldPlay(old: 0, new: 5, tracksInventory: true, alreadyCelebrated: false))
        #expect(!FirstOwnedCelebration.shouldPlay(old: 1, new: 0, tracksInventory: true, alreadyCelebrated: false))
    }
}
