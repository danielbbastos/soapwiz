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

    private static func makeField(_ keyboardType: UIKeyboardType) -> UITextField {
        let field = UITextField()
        field.keyboardType = keyboardType
        return field
    }

    @Test func presetTargets_TouchedNumberField_ReturnsField() {
        let field = Self.makeField(.decimalPad)

        let targets = NumberPadPopoverPresetRecognizer.presetTargets(for: field, idiom: .pad)

        #expect(targets.count == 1)
        #expect(targets.first === field)
    }

    @Test func presetTargets_SubviewInsideField_ReturnsField() {
        let field = Self.makeField(.numberPad)
        let inner = UIView()
        field.addSubview(inner)

        let targets = NumberPadPopoverPresetRecognizer.presetTargets(for: inner, idiom: .pad)

        #expect(targets.count == 1)
        #expect(targets.first === field)
    }

    @Test func presetTargets_PaddingInCollectionViewCell_ReturnsOnlyNumberField() throws {
        let cell = UICollectionViewCell()
        let padding = UIView()
        let numberField = Self.makeField(.decimalPad)
        let nameField = Self.makeField(.default)
        let container = UIView()
        cell.contentView.addSubview(padding)
        cell.contentView.addSubview(container)
        container.addSubview(numberField)
        container.addSubview(nameField)

        let targets = NumberPadPopoverPresetRecognizer.presetTargets(for: padding, idiom: .pad)

        #expect(targets.count == 1)
        #expect(try #require(targets.first) === numberField)
    }

    @Test func presetTargets_PaddingInTableViewCell_ReturnsOnlyNumberField() throws {
        let cell = UITableViewCell()
        let padding = UIView()
        let numberField = Self.makeField(.numberPad)
        let nameField = Self.makeField(.default)
        cell.contentView.addSubview(padding)
        cell.contentView.addSubview(numberField)
        cell.contentView.addSubview(nameField)

        let targets = NumberPadPopoverPresetRecognizer.presetTargets(for: padding, idiom: .pad)

        #expect(targets.count == 1)
        #expect(try #require(targets.first) === numberField)
    }

    @Test func presetTargets_PlainViewOutsideCell_ReturnsEmpty() {
        let view = UIView()
        view.addSubview(Self.makeField(.decimalPad))

        #expect(NumberPadPopoverPresetRecognizer.presetTargets(for: view, idiom: .pad).isEmpty)
    }

    @Test func presetTargets_NilView_ReturnsEmpty() {
        #expect(NumberPadPopoverPresetRecognizer.presetTargets(for: nil, idiom: .pad).isEmpty)
    }

    @Test func presetTargets_PhoneIdiom_ReturnsEmpty() {
        let field = Self.makeField(.decimalPad)

        #expect(NumberPadPopoverPresetRecognizer.presetTargets(for: field, idiom: .phone).isEmpty)
    }

    @Test func presetTargets_TouchedDefaultKeyboardField_ReturnsEmpty() {
        let field = Self.makeField(.default)

        #expect(NumberPadPopoverPresetRecognizer.presetTargets(for: field, idiom: .pad).isEmpty)
    }
}
