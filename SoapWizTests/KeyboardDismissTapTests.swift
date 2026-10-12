import Testing
import UIKit
@testable import SoapWiz

@Suite
struct KeyboardDismissTapTests {

    @Test func shouldEndEditing_PlainView_ReturnsTrue() {
        let field = UITextField()
        let plain = UIView()

        #expect(KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: plain, firstResponder: field))
    }

    @Test func shouldEndEditing_TouchedViewIsTextField_ReturnsFalse() {
        let focused = UITextField()
        let other = UITextField()

        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: other, firstResponder: focused))
    }

    @Test func shouldEndEditing_TouchedViewInsideTextView_ReturnsFalse() {
        let textView = UITextView()
        let inner = UIView()
        textView.addSubview(inner)

        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: inner, firstResponder: UITextField()))
    }

    @Test func shouldEndEditing_ResponderIsSearchTextField_ReturnsFalse() {
        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: UIView(), firstResponder: UISearchTextField()))
    }

    @Test func shouldEndEditing_ResponderHasSearchReturnKey_ReturnsFalse() {
        let field = UITextField()
        field.returnKeyType = .search

        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: UIView(), firstResponder: field))
    }

    @Test func shouldEndEditing_NilResponder_ReturnsFalse() {
        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: UIView(), firstResponder: nil))
    }

    @Test func shouldEndEditing_NilTouchedView_ReturnsFalse() {
        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: nil, firstResponder: UITextField()))
    }

    @Test func shouldEndEditing_NonViewResponder_ReturnsFalse() {
        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: UIView(), firstResponder: UIResponder()))
    }

    @Test func shouldEndEditing_SameCollectionViewCell_ReturnsFalse() {
        let cell = UICollectionViewCell()
        let field = UITextField()
        let padding = UIView()
        cell.contentView.addSubview(field)
        cell.contentView.addSubview(padding)

        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: padding, firstResponder: field))
    }

    @Test func shouldEndEditing_DifferentCollectionViewCell_ReturnsTrue() {
        let fieldCell = UICollectionViewCell()
        let otherCell = UICollectionViewCell()
        let field = UITextField()
        let padding = UIView()
        fieldCell.contentView.addSubview(field)
        otherCell.contentView.addSubview(padding)

        #expect(KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: padding, firstResponder: field))
    }

    @Test func shouldEndEditing_SameTableViewCell_ReturnsFalse() {
        let cell = UITableViewCell()
        let field = UITextField()
        let padding = UIView()
        cell.contentView.addSubview(field)
        cell.contentView.addSubview(padding)

        #expect(!KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: padding, firstResponder: field))
    }

    @Test func shouldEndEditing_ButtonOutsideRespondersCell_ReturnsTrue() {
        let cell = UICollectionViewCell()
        let field = UITextField()
        cell.contentView.addSubview(field)
        let button = UIButton()

        #expect(KeyboardDismissTapRecognizer.shouldEndEditing(touchedView: button, firstResponder: field))
    }
}
