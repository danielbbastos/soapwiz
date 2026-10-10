import CoreGraphics
import Testing
@testable import SoapWiz

@Suite
struct HeaderStripSubtitleCollapseTests {

    private func collapsed(
        was wasCollapsed: Bool,
        offset: CGFloat,
        height: CGFloat = 40
    ) -> Bool {
        HeaderStripSubtitleCollapse.isCollapsed(wasCollapsed: wasCollapsed, offset: offset, subtitleHeight: height)
    }

    @Test func isCollapsed_AtRest_StaysExpanded() {
        #expect(!collapsed(was: false, offset: 0))
    }

    @Test(arguments: [CGFloat(1), 20, 40, 48])
    func isCollapsed_ScrollWithinHeightAndMargin_StaysExpanded(offset: CGFloat) {
        #expect(!collapsed(was: false, offset: offset))
    }

    @Test(arguments: [CGFloat(49), 60, 500])
    func isCollapsed_PastThreshold_Collapses(offset: CGFloat) {
        #expect(collapsed(was: false, offset: offset))
    }

    @Test(arguments: [CGFloat(0.5), 1, 20, 48, 49, 300])
    func isCollapsed_WhileOffsetAboveTop_StaysCollapsed(offset: CGFloat) {
        #expect(collapsed(was: true, offset: offset))
    }

    @Test(arguments: [CGFloat(0), -1, -80])
    func isCollapsed_AtTopOrOverscroll_Expands(offset: CGFloat) {
        #expect(!collapsed(was: true, offset: offset))
    }

    @Test func isCollapsed_HeightNotMeasured_CollapsesPastMargin() {
        #expect(!collapsed(was: false, offset: 8, height: 0))
        #expect(collapsed(was: false, offset: 9, height: 0))
    }

    @Test func isCollapsed_CollapseShiftsOffsetDownByHeight_DoesNotFlipBack() {
        let height: CGFloat = 40
        let offset: CGFloat = 49
        #expect(collapsed(was: false, offset: offset, height: height))
        #expect(collapsed(was: true, offset: offset - height, height: height))
    }

    @Test func isCollapsed_ExpandShiftsOffsetUpByHeight_DoesNotCollapseAgain() {
        let height: CGFloat = 40
        #expect(!collapsed(was: true, offset: 0, height: height))
        #expect(!collapsed(was: false, offset: 0 + height, height: height))
    }
}
