import UIKit
import Testing
@testable import SoapWiz

@Suite @MainActor
struct LedgerRowTouchTrackerViewTests {

    @Test func recognizer_NoEnclosingCell_ReturnsNil() {
        let sut = LedgerRowTouchTrackerView()
        UIView().addSubview(sut)

        #expect(sut.recognizerOnEnclosingCell() == nil)
    }

    @Test func recognizer_InsideCell_InstallsOneOnTheCell() throws {
        let cell = UICollectionViewCell()
        let sut = LedgerRowTouchTrackerView()
        cell.contentView.addSubview(sut)

        let recognizer = try #require(sut.recognizerOnEnclosingCell())

        #expect(recognizer.view === cell)
        #expect(cell.gestureRecognizers?.count == 1)
    }

    @Test func recognizer_InsideTableViewCell_InstallsOneOnTheCell() throws {
        let cell = UITableViewCell()
        let sut = LedgerRowTouchTrackerView()
        cell.contentView.addSubview(sut)

        let recognizer = try #require(sut.recognizerOnEnclosingCell())

        #expect(recognizer.view === cell)
    }

    @Test func recognizer_RepeatedCalls_LooksUpOnce() throws {
        let cell = UICollectionViewCell()
        let sut = LedgerRowTouchTrackerView()
        cell.contentView.addSubview(sut)

        let first = try #require(sut.recognizerOnEnclosingCell())
        let second = try #require(sut.recognizerOnEnclosingCell())
        _ = sut.recognizerOnEnclosingCell()

        #expect(first === second)
        #expect(sut.lookupCount == 1)
    }

    @Test func recognizer_TwoViewsInOneCell_ShareTheRecognizer() throws {
        let cell = UICollectionViewCell()
        let first = LedgerRowTouchTrackerView()
        let second = LedgerRowTouchTrackerView()
        cell.contentView.addSubview(first)
        cell.contentView.addSubview(second)

        let one = try #require(first.recognizerOnEnclosingCell())
        let two = try #require(second.recognizerOnEnclosingCell())

        #expect(one === two)
        #expect(cell.gestureRecognizers?.count == 1)
    }

    @Test func recognizer_MovedToAnotherCell_UsesTheNewCellsRecognizer() throws {
        let oldCell = UICollectionViewCell()
        let newCell = UICollectionViewCell()
        let sut = LedgerRowTouchTrackerView()
        oldCell.contentView.addSubview(sut)
        let old = try #require(sut.recognizerOnEnclosingCell())

        newCell.contentView.addSubview(sut)
        let new = try #require(sut.recognizerOnEnclosingCell())

        #expect(old.view === oldCell)
        #expect(new.view === newCell)
        #expect(old !== new)
        #expect(sut.lookupCount == 2)
    }

    @Test func recognizer_RemovedFromCell_LooksAgainAndFindsNone() throws {
        let cell = UICollectionViewCell()
        let sut = LedgerRowTouchTrackerView()
        cell.contentView.addSubview(sut)
        _ = try #require(sut.recognizerOnEnclosingCell())

        sut.removeFromSuperview()

        #expect(sut.recognizerOnEnclosingCell() == nil)
    }

    @Test func recognizer_AncestorMovedWithoutViewMoving_NoLongerUsesOldCell() throws {
        let oldCell = UICollectionViewCell()
        let newCell = UICollectionViewCell()
        let wrapper = UIView()
        let sut = LedgerRowTouchTrackerView()
        wrapper.addSubview(sut)
        oldCell.contentView.addSubview(wrapper)
        _ = try #require(sut.recognizerOnEnclosingCell())

        newCell.contentView.addSubview(wrapper)
        let moved = try #require(sut.recognizerOnEnclosingCell())

        #expect(moved.view === newCell)
    }
}

@Suite
struct LedgerRowTouchRecognizerTests {

    @Test func exceedsSlop_NoMovement_IsFalse() {
        #expect(!LedgerRowTouchRecognizer.exceedsSlop(from: .zero, to: .zero))
    }

    @Test func exceedsSlop_AtSlop_IsFalse() {
        let point = CGPoint(x: 6, y: 8)
        #expect(!LedgerRowTouchRecognizer.exceedsSlop(from: .zero, to: point))
    }

    @Test func exceedsSlop_JustPastSlop_IsTrue() {
        let point = CGPoint(x: 0, y: LedgerRowTouchRecognizer.slop + 0.5)
        #expect(LedgerRowTouchRecognizer.exceedsSlop(from: .zero, to: point))
    }

    @Test func exceedsSlop_Diagonal_MeasuresDistance() {
        #expect(LedgerRowTouchRecognizer.exceedsSlop(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 18, y: 18)))
        #expect(!LedgerRowTouchRecognizer.exceedsSlop(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 16, y: 16)))
    }
}
