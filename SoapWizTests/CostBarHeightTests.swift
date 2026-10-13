import Testing
import CoreGraphics
@testable import SoapWiz

@Suite
struct CostBarHeightTests {

    @Test func panelCarouselHeight_ZeroExtra_ReturnsDefault() {
        #expect(Self.height(extra: 0) == 300)
    }

    @Test func panelCarouselHeight_NegativeExtra_ReturnsDefault() {
        #expect(Self.height(extra: -80) == 300)
    }

    @Test func panelCarouselHeight_ExtraWithinRange_AddsToDefault() {
        #expect(Self.height(extra: 120) == 420)
    }

    @Test func panelCarouselHeight_ExtraReachingMaximum_ReturnsMaximum() {
        #expect(Self.height(extra: 200) == 500)
    }

    @Test func panelCarouselHeight_ExtraPastMaximum_ReturnsMaximum() {
        #expect(Self.height(extra: 900) == 500)
    }

    @Test func panelCarouselHeight_MaximumBelowDefault_ReturnsDefault() {
        #expect(Self.height(extra: 100, maximum: 250) == 300)
    }

    @Test func panelCarouselHeight_NoMeasuredMaximum_ReturnsDefault() {
        #expect(Self.height(extra: 100, maximum: 0) == 300)
    }

    @Test func panelCarouselHeight_ContentBelowRoom_CapsAtContent() {
        #expect(Self.height(extra: 900, content: 400) == 400)
    }

    @Test func panelCarouselHeight_ContentAboveRoom_CapsAtRoom() {
        #expect(Self.height(extra: 900, content: 800) == 500)
    }

    @Test func panelCarouselHeight_ContentBelowDefault_ReturnsDefault() {
        #expect(Self.height(extra: 900, content: 200) == 300)
    }

    @Test func panelCarouselHeight_ContentNotMeasured_DoesNotCap() {
        #expect(Self.height(extra: 900, content: 0) == 500)
    }

    @Test func carouselUpperBound_ContentBelowMaximum_ReturnsContent() {
        #expect(CostBreakdownBarInset.carouselUpperBound(maximum: 500, contentHeight: 350) == 350)
    }

    @Test func carouselUpperBound_ContentNotMeasured_ReturnsMaximum() {
        #expect(CostBreakdownBarInset.carouselUpperBound(maximum: 500, contentHeight: 0) == 500)
    }

    @Test(arguments: [
        (false, false, false, 0.4), (false, true, false, 0.4),
        (true, false, false, 0.4), (true, true, false, 0.3),
        (false, false, true, 0.3), (false, true, true, 0.3),
        (true, false, true, 0.3), (true, true, true, 0.3)
    ])
    func defaultCarouselFraction_AllCombinations_ReturnsExpected(
        isRegular: Bool, isLandscape: Bool, keyboardVisible: Bool, expected: CGFloat
    ) {
        #expect(CostBreakdownBarInset.defaultCarouselFraction(
            isRegular: isRegular, isLandscape: isLandscape, keyboardVisible: keyboardVisible
        ) == expected)
    }

    private static func height(extra: CGFloat, maximum: CGFloat = 500, content: CGFloat = 0) -> CGFloat {
        CostBreakdownBarInset.panelCarouselHeight(
            defaultHeight: 300, extraHeight: extra, maximum: maximum, contentHeight: content
        )
    }
}
