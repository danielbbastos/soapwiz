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

    /// Centring alone would leave less than the list's own margin here, so the
    /// content would grow wider as the window grows. It keeps the system margin.
    @Test(arguments: [CGFloat(701), 704, 720, 739.5, 740])
    func margin_JustOverTheCap_KeepsTheSystemMargin(width: CGFloat) {
        #expect(ReadableWidth.margin(for: width) == nil)
    }

    /// At the switch, the system margin and the cap give the same content width.
    @Test func margin_AtTheSwitch_ContentStaysAtTheCap() throws {
        let justBefore: CGFloat = 740
        let justAfter: CGFloat = 742
        let margin = try #require(ReadableWidth.margin(for: justAfter))

        #expect(justBefore - 2 * ReadableWidth.systemMargin == ReadableWidth.maximum)
        #expect(justAfter - 2 * margin == ReadableWidth.maximum)
        #expect(margin > ReadableWidth.systemMargin)
    }

    @Test func margin_WithInset_SubtractsTheContentsOwnPadding() {
        #expect(ReadableWidth.margin(for: 1_180, inset: 16) == 224)
    }

    @Test func margin_WithInsetJustPastTheSwitch_StaysPositive() throws {
        let margin = try #require(ReadableWidth.margin(for: 742, inset: 16))

        #expect(margin == 5)
    }

    @Test func margin_WithInsetBeforeTheSwitch_LeavesTheSystemMargin() {
        #expect(ReadableWidth.margin(for: 730, inset: 16) == nil)
    }
}
