import Testing
import SwiftUI
@testable import SoapWiz

/// A tab's list and detail across a window-width change (SW-89): the open item
/// carries over between pushed and beside-the-list, and nothing else does.
@Suite("ListDetailNavigation")
@MainActor
struct ListDetailNavigationTests {

    private let sut = ListDetailNavigation<String>()

    // MARK: - Layout threshold

    @Test(arguments: [
        (CGFloat(0), false),
        (820, false),
        (999.5, false),
        (1_000, true),
        (1_032, true),
        (1_180, true)
    ])
    func isWide_ByWidth_WideFromThreshold(width: CGFloat, expected: Bool) {
        #expect(ListDetailLayout.isWide(width: width) == expected)
    }

    // MARK: - Showing an item

    @Test func initialState_NarrowWithNothingOpen() {
        #expect(!sut.isWide)
        #expect(sut.selection == nil)
        #expect(sut.path.isEmpty)
    }

    @Test func show_Narrow_PushesTheItemAlone() {
        sut.path.append("Deeper")

        sut.show("Castile")

        #expect(sut.selection == "Castile")
        #expect(sut.path.count == 1)
    }

    @Test func show_Wide_SelectsWithoutPushing() {
        sut.setWide(true)
        sut.path.append("Deeper")

        sut.show("Castile")

        #expect(sut.selection == "Castile")
        #expect(sut.path.isEmpty)
    }

    @Test func isOpenBeside_WideAndSelected_IsTrueForThatItemOnly() {
        sut.setWide(true)
        sut.show("Castile")

        #expect(sut.isOpenBeside("Castile"))
        #expect(!sut.isOpenBeside("Marseille"))
    }

    @Test func isOpenBeside_NarrowWithItemPushed_IsFalse() {
        sut.show("Castile")

        #expect(!sut.isOpenBeside("Castile"))
    }

    // MARK: - Detail identity

    @Test func show_DifferentItem_GivesTheDetailANewIdentity() {
        sut.show("Castile")
        let first = sut.detailID

        sut.show("Marseille")

        #expect(sut.detailID != first)
    }

    @Test func show_SameItemAgain_KeepsTheDetailIdentity() {
        sut.setWide(true)
        sut.show("Castile")
        let first = sut.detailID

        sut.show("Castile")

        #expect(sut.detailID == first)
    }

    @Test func replaceSelection_KeepsPathAndDetailIdentity() {
        sut.show("Castile")
        sut.path.append("Purchase")
        let first = sut.detailID

        sut.replaceSelection(with: "Castile (survivor)")

        #expect(sut.selection == "Castile (survivor)")
        #expect(sut.path.count == 2)
        #expect(sut.detailID == first)
    }

    @Test func replaceSelection_ThenNarrowToWide_KeepsTheReplacement() {
        sut.show("Castile")
        sut.replaceSelection(with: "Castile (survivor)")

        sut.setWide(true)

        #expect(sut.isOpenBeside("Castile (survivor)"))
        #expect(!sut.isOpenBeside("Castile"))
    }

    // MARK: - Width changes

    @Test func setWide_NarrowToWide_KeepsTheOpenItemAsSelection() {
        sut.show("Castile")

        sut.setWide(true)

        #expect(sut.isWide)
        #expect(sut.selection == "Castile")
        #expect(sut.path.isEmpty)
    }

    @Test func setWide_WideToNarrow_PushesTheSelection() {
        sut.setWide(true)
        sut.show("Castile")

        sut.setWide(false)

        #expect(!sut.isWide)
        #expect(sut.selection == "Castile")
        #expect(sut.path.count == 1)
    }

    @Test func setWide_WideToNarrowWithNothingSelected_ShowsTheList() {
        sut.setWide(true)

        sut.setWide(false)

        #expect(sut.selection == nil)
        #expect(sut.path.isEmpty)
    }

    @Test func setWide_DeeperScreens_AreDropped() {
        sut.show("Castile")
        sut.path.append("Batch")

        sut.setWide(true)

        #expect(sut.selection == "Castile")
        #expect(sut.path.isEmpty)
    }

    @Test func setWide_SameWidthClass_LeavesThePathAlone() {
        sut.show("Castile")
        sut.path.append("Batch")

        sut.setWide(false)

        #expect(sut.path.count == 2)
    }

    @Test func setWide_RoundTrip_KeepsTheSelection() {
        sut.show("Castile")

        sut.setWide(true)
        sut.setWide(false)

        #expect(sut.selection == "Castile")
        #expect(sut.path.count == 1)
    }

    // MARK: - Going back

    @Test func pathDidChange_NarrowPoppedToList_Deselects() {
        sut.show("Castile")
        sut.path = NavigationPath()

        sut.pathDidChange()

        #expect(sut.selection == nil)
    }

    @Test func pathDidChange_NarrowStillOnDetail_KeepsSelection() {
        sut.show("Castile")
        sut.path.append("Batch")
        sut.path.removeLast()

        sut.pathDidChange()

        #expect(sut.selection == "Castile")
    }

    @Test func pathDidChange_WideEmptyPath_KeepsSelection() {
        sut.setWide(true)
        sut.show("Castile")

        sut.pathDidChange()

        #expect(sut.selection == "Castile")
    }

    @Test func reset_ClearsSelectionAndPath() {
        sut.show("Castile")
        sut.path.append("Batch")

        sut.reset()

        #expect(sut.selection == nil)
        #expect(sut.path.isEmpty)
    }

    // MARK: - Deletion

    @Test func close_ShowingOneOfTheItems_ClosesTheDetail() {
        sut.setWide(true)
        sut.show("Castile")

        sut.close(ifShowingAnyOf: ["Marseille", "Castile"])

        #expect(sut.selection == nil)
        #expect(sut.path.isEmpty)
    }

    @Test func close_ShowingAnotherItem_KeepsTheDetail() {
        sut.setWide(true)
        sut.show("Castile")
        sut.path.append("Batch")

        sut.close(ifShowingAnyOf: ["Marseille"])

        #expect(sut.selection == "Castile")
        #expect(sut.path.count == 1)
    }

    @Test func close_NoItems_KeepsTheDetail() {
        sut.show("Castile")

        sut.close(ifShowingAnyOf: [])

        #expect(sut.selection == "Castile")
    }

    @Test func close_NothingSelected_LeavesThePathAlone() {
        sut.path.append("New recipe form")

        sut.close(ifShowingAnyOf: ["Castile"])

        #expect(sut.path.count == 1)
    }

    @Test func prune_SelectionGone_ClosesTheDetail() {
        sut.setWide(true)
        sut.show("Castile")

        sut.prune(keeping: ["Marseille"])

        #expect(sut.selection == nil)
        #expect(sut.path.isEmpty)
    }

    @Test func prune_SelectionStillThere_KeepsIt() {
        sut.show("Castile")
        sut.path.append("Batch")

        sut.prune(keeping: ["Castile", "Marseille"])

        #expect(sut.selection == "Castile")
        #expect(sut.path.count == 2)
    }

    @Test func prune_EmptyList_ClosesTheDetail() {
        sut.show("Castile")

        sut.prune(keeping: [])

        #expect(sut.selection == nil)
    }

    @Test func prune_NothingSelected_LeavesThePathAlone() {
        sut.path.append("New recipe form")

        sut.prune(keeping: [])

        #expect(sut.path.count == 1)
    }
}
