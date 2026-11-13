import SwiftUI
import Testing
@testable import SoapWiz

@Suite
struct HomeLayoutTests {
    @Test func isWide_BelowThreshold_ReturnsFalse() {
        #expect(!HomeLayout.isWide(width: 999, dynamicTypeSize: .large))
    }

    @Test func isWide_AtThreshold_ReturnsTrue() {
        #expect(HomeLayout.isWide(width: 1_000, dynamicTypeSize: .large))
    }

    @Test func isWide_AboveThreshold_ReturnsTrue() {
        #expect(HomeLayout.isWide(width: 1_366, dynamicTypeSize: .xxxLarge))
    }

    @Test func isWide_AccessibilitySize_ReturnsFalse() {
        #expect(!HomeLayout.isWide(width: 1_366, dynamicTypeSize: .accessibility1))
        #expect(!HomeLayout.isWide(width: 1_366, dynamicTypeSize: .accessibility5))
    }

    @Test func isWide_NarrowAndAccessibilitySize_ReturnsFalse() {
        #expect(!HomeLayout.isWide(width: 390, dynamicTypeSize: .accessibility3))
    }

    @Test func titleMargin_AccessibilitySize_FallsBackToReadableMargin() {
        let readable = ReadableWidth.margin(for: 1_180)
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: false, dynamicTypeSize: .accessibility1) == readable)
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: true, dynamicTypeSize: .accessibility1) == readable)
    }
}

@Suite
struct HomeColumnsLayoutTests {
    private let spacing = HomeLayout.spacing

    @Test func frames_OneColumn_StacksFullWidth() {
        let frames = HomeColumnsLayout.frames(heights: [100, 50, 70], width: 400, columnCount: 1)
        #expect(frames == [
            CGRect(x: 0, y: 0, width: 400, height: 100),
            CGRect(x: 0, y: 100 + spacing, width: 400, height: 50),
            CGRect(x: 0, y: 150 + 2 * spacing, width: 400, height: 70)
        ])
    }

    @Test func frames_OneColumn_IsNotCappedWhenWide() {
        let frames = HomeColumnsLayout.frames(heights: [10], width: 2_000, columnCount: 1)
        #expect(frames.first?.width == 2_000)
        #expect(frames.first?.minX == 0)
    }

    @Test func frames_ThreeColumns_SplitsWidthAndTopAligns() {
        let width: CGFloat = 1_000
        let column = (width - 2 * spacing) / 3
        let frames = HomeColumnsLayout.frames(heights: [100, 200, 50], width: width, columnCount: 3)
        #expect(frames.map(\.width) == [column, column, column])
        #expect(frames.map(\.minY) == [0, 0, 0])
        #expect(frames.map(\.minX) == [0, column + spacing, 2 * (column + spacing)])
        #expect(frames.map(\.height) == [100, 200, 50])
    }

    @Test func frames_ThreeColumns_SecondRowStartsBelowTallestInFirst() {
        let frames = HomeColumnsLayout.frames(heights: [100, 200, 50, 80], width: 1_000, columnCount: 3)
        #expect(frames.count == 4)
        #expect(frames[3].minY == 200 + spacing)
        #expect(frames[3].minX == 0)
    }

    @Test func frames_ThreeColumns_CapsAndCentresAtMaximumWidth() {
        let width: CGFloat = 1_400
        let column = (HomeLayout.maximumWidth - 2 * spacing) / 3
        let frames = HomeColumnsLayout.frames(heights: [10, 10, 10], width: width, columnCount: 3)
        let inset = (width - HomeLayout.maximumWidth) / 2
        #expect(frames[0].minX == inset)
        #expect(frames[0].width == column)
        #expect(frames[2].maxX == width - inset)
    }

    @Test func frames_ThreeColumns_BelowCapFillsWidth() {
        let frames = HomeColumnsLayout.frames(heights: [10, 10, 10], width: 1_000, columnCount: 3)
        #expect(frames[0].minX == 0)
        #expect(frames[2].maxX == 1_000)
    }

    @Test func frames_NoCards_ReturnsEmpty() {
        #expect(HomeColumnsLayout.frames(heights: [], width: 1_000, columnCount: 3).isEmpty)
    }

    @Test func frames_SingleCardThreeColumns_UsesFirstColumn() {
        let width: CGFloat = 1_000
        let frames = HomeColumnsLayout.frames(heights: [40], width: width, columnCount: 3)
        #expect(frames.count == 1)
        #expect(frames[0].minX == 0)
        #expect(frames[0].width == (width - 2 * spacing) / 3)
    }
}

@Suite
struct InsightsColumnsLayoutTests {
    private let spacing = HomeLayout.spacing

    @Test func frames_Wide_FirstSpansTwoColumnsSecondTakesThird() {
        let width: CGFloat = 1_000
        let column = (width - 2 * spacing) / 3
        let frames = InsightsColumnsLayout.frames(heights: [300, 200], width: width, isWide: true)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 2 * column + spacing, height: 300))
        #expect(frames[1] == CGRect(x: 2 * column + 2 * spacing, y: 0, width: column, height: 200))
        #expect(frames[1].maxX == width)
    }

    @Test func frames_Wide_SingleCardSpansAllThreeColumns() {
        let width: CGFloat = 1_000
        let frames = InsightsColumnsLayout.frames(heights: [300], width: width, isWide: true)
        #expect(frames == [CGRect(x: 0, y: 0, width: width, height: 300)])
    }

    @Test func frames_Stacked_FullWidthWithSpacing() {
        let frames = InsightsColumnsLayout.frames(heights: [300, 200], width: 400, isWide: false)
        #expect(frames == [
            CGRect(x: 0, y: 0, width: 400, height: 300),
            CGRect(x: 0, y: 300 + spacing, width: 400, height: 200)
        ])
    }

    @Test func frames_NoCards_ReturnsEmpty() {
        #expect(InsightsColumnsLayout.frames(heights: [], width: 400, isWide: true).isEmpty)
        #expect(InsightsColumnsLayout.frames(heights: [], width: 400, isWide: false).isEmpty)
    }
}
