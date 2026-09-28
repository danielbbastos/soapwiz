import Testing
import CoreGraphics
@testable import SoapWiz

/// The margin that caps a screen's content at a readable width on iPad (SW-89).
@Suite("ReadableWidth")
struct ReadableWidthTests {

    @Test(arguments: [CGFloat(0), 320, 393, 380, 580, 700])
    func margin_AtOrBelowTheCap_LeavesTheSystemMargin(width: CGFloat) {
        #expect(ReadableWidth.margin(for: width) == nil)
    }

    @Test(arguments: [
        (CGFloat(820), CGFloat(60)),
        (1_032, 166),
        (1_180, 240),
        (1_376, 338)
    ])
    func margin_WiderThanTheCap_CentresTheContent(width: CGFloat, expected: CGFloat) {
        #expect(ReadableWidth.margin(for: width) == expected)
    }

    @Test func margin_JustOverTheCap_IsSmallAndPositive() throws {
        let margin = try #require(ReadableWidth.margin(for: 702))

        #expect(margin == 1)
    }

    @Test func margin_WithInset_SubtractsTheContentsOwnPadding() {
        #expect(ReadableWidth.margin(for: 1_180, inset: 16) == 224)
    }

    @Test func margin_InsetLargerThanTheMargin_NeverGoesNegative() {
        #expect(ReadableWidth.margin(for: 710, inset: 16) == 0)
    }

    @Test func margin_WithInsetAtOrBelowTheCap_LeavesTheSystemMargin() {
        #expect(ReadableWidth.margin(for: 700, inset: 16) == nil)
    }
}
