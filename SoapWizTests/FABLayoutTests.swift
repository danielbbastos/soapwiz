import CoreGraphics
import Testing
@testable import SoapWiz

@Suite
struct FABLayoutTests {
    private func action(_ label: String) -> FABAction {
        FABAction(label: label, systemImage: "plus") { }
    }

    @Test func pillOrder_PrimaryLastAndSecondaryReversed() {
        let order = FABLayout.pillOrder(
            primary: action("Add"),
            secondary: [action("First"), action("Second")]
        )

        #expect(order.map(\.label) == ["Second", "First", "Add"])
    }

    @Test func pillOrder_NoSecondary_IsPrimaryOnly() {
        let order = FABLayout.pillOrder(primary: action("Add"), secondary: [])

        #expect(order.map(\.label) == ["Add"])
    }

    @Test(arguments: [(2, CGFloat(64)), (1, CGFloat(124)), (0, CGFloat(184))])
    func emergenceOffset_SumsPillsBelowPlusHalfCircle(index: Int, expected: CGFloat) {
        let offset = FABLayout.emergenceOffset(heights: [48, 48, 48], index: index, spacing: 12, diameter: 56)

        #expect(offset == expected)
    }

    @Test func emergenceOffset_IndexOutOfRange_IsZero() {
        #expect(FABLayout.emergenceOffset(heights: [48], index: 3, spacing: 12, diameter: 56) == 0)
    }

    @Test func staggerDelay_OpeningStartsNearestTheCircle() {
        let delays = (0..<3).map { FABLayout.staggerDelay(index: $0, count: 3, isOpening: true) }

        #expect(delays == [0.06, 0.03, 0])
    }

    @Test func staggerDelay_ClosingStartsAtTheTop() {
        let delays = (0..<3).map { FABLayout.staggerDelay(index: $0, count: 3, isOpening: false) }

        #expect(delays == [0, 0.03, 0.06])
    }

    @Test func circleLabel_ChangesWithExpansionOnlyWhenThereAreSecondaryActions() {
        let collapsed = FABLayout.circleLabel(hasSecondaryActions: true, isExpanded: false)
        let expanded = FABLayout.circleLabel(hasSecondaryActions: true, isExpanded: true)
        let plain = FABLayout.circleLabel(hasSecondaryActions: false, isExpanded: false)

        #expect(collapsed != expanded)
        #expect(collapsed != plain)
        #expect(plain == FABLayout.circleLabel(hasSecondaryActions: false, isExpanded: true))
    }
}
