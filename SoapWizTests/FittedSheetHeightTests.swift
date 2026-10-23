import Testing
import CoreGraphics
@testable import SoapWiz

@Suite
struct FittedSheetHeightTests {

    @Test func height_ContentShorterThanCap_ReturnsContentHeight() throws {
        let result = try #require(FittedSheetHeight.height(content: 400, available: 1180))
        #expect(result == 400)
    }

    @Test func height_ContentTallerThanCap_ReturnsCap() throws {
        let result = try #require(FittedSheetHeight.height(content: 2000, available: 1180))
        #expect(result == 826)
    }

    @Test func height_ContentExactlyAtCap_ReturnsCap() throws {
        let result = try #require(FittedSheetHeight.height(content: 826, available: 1180))
        #expect(result == 826)
    }

    @Test(arguments: [
        (nil, 1180),
        (0, 1180),
        (400, 0),
        (400, -100)
    ] as [(CGFloat?, CGFloat)])
    func height_UnusableInput_ReturnsNil(content: CGFloat?, available: CGFloat) {
        #expect(FittedSheetHeight.height(content: content, available: available) == nil)
    }

    @Test func height_LandscapeHeight_CapsAtSeventyPercent() throws {
        let result = try #require(FittedSheetHeight.height(content: 2000, available: 820))
        #expect(abs(result - 574) < 0.001)
    }
}
