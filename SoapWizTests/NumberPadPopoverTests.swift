import Testing
import UIKit
@testable import SoapWiz

@Suite
struct NumberPadPopoverTests {

    private static let numberPads: [UIKeyboardType] = [.numberPad, .decimalPad, .asciiCapableNumberPad]
    private static let otherKeyboards: [UIKeyboardType] = [.default, .emailAddress, .numbersAndPunctuation, .URL]

    @Test(arguments: numberPads)
    func suppresses_NumberPadOnPad_ReturnsTrue(keyboardType: UIKeyboardType) {
        #expect(UITextField.suppressesNumberPadPopover(keyboardType: keyboardType, idiom: .pad))
    }

    @Test(arguments: numberPads)
    func suppresses_NumberPadOnPhone_ReturnsFalse(keyboardType: UIKeyboardType) {
        #expect(!UITextField.suppressesNumberPadPopover(keyboardType: keyboardType, idiom: .phone))
    }

    @Test(arguments: otherKeyboards)
    func suppresses_OtherKeyboardOnPad_ReturnsFalse(keyboardType: UIKeyboardType) {
        #expect(!UITextField.suppressesNumberPadPopover(keyboardType: keyboardType, idiom: .pad))
    }
}
