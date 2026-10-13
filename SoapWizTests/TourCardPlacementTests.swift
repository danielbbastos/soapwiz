import CoreGraphics
import Testing
@testable import SoapWiz

@Suite
struct TourCardPlacementTests {

    private let phone = CGSize(width: 390, height: 844)
    private let phoneInsets = TourSafeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    private let pad = CGSize(width: 1180, height: 820)
    private let padInsets = TourSafeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
    private let fab = CGRect(x: 308, y: 680, width: 68, height: 68)

    private func phonePlacement(
        cutouts: [CGRect],
        cardHeight: CGFloat = 200
    ) -> TourCardPlacement.Result {
        TourCardPlacement.place(
            container: phone,
            safeInsets: phoneInsets,
            cutouts: cutouts,
            cardSize: CGSize(width: 358, height: cardHeight),
            allowsSide: false
        )
    }

    private func padPlacement(
        cutouts: [CGRect],
        cardHeight: CGFloat = 200,
        allowsSide: Bool = true
    ) -> TourCardPlacement.Result {
        TourCardPlacement.place(
            container: pad,
            safeInsets: padInsets,
            cutouts: cutouts,
            cardSize: CGSize(width: 400, height: cardHeight),
            allowsSide: allowsSide
        )
    }

    private func cardRect(_ result: TourCardPlacement.Result, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: result.origin.x, y: result.origin.y, width: width, height: min(height, result.maxHeight ?? height))
    }

    private func inflated(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -TourCardPlacement.cutoutInflation, dy: -TourCardPlacement.cutoutInflation)
    }

    @Test(arguments: [(390.0, 358.0), (1180.0, 400.0), (420.0, 388.0)])
    func cardWidth_ContainerWidth_ReturnsCappedWidth(containerWidth: CGFloat, expected: CGFloat) {
        #expect(TourCardPlacement.cardWidth(for: containerWidth) == expected)
    }

    @Test func place_CutoutNearTop_PlacesBelowWithGap() {
        let cutout = CGRect(x: 12, y: 180, width: 366, height: 52)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.edge == .below)
        #expect(result.origin.y == cutout.maxY + TourCardPlacement.gap)
        #expect(result.maxHeight == nil)
    }

    @Test func place_CutoutNearBottom_PlacesAbove() {
        let cutout = CGRect(x: 12, y: 700, width: 366, height: 60)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.edge == .above)
        #expect(result.origin.y + 200 == cutout.minY - TourCardPlacement.gap)
        #expect(result.maxHeight == nil)
    }

    @Test func place_Step1Shape_SearchAndFab_PlacesBelow() {
        let search = CGRect(x: 12, y: 180, width: 366, height: 52)

        let result = phonePlacement(cutouts: [search, fab])

        #expect(result.edge == .below)
        #expect(result.maxHeight == nil)
    }

    @Test func place_Step2Shape_BelowWouldHitFab_PlacesAbove() {
        let purchase = CGRect(x: 12, y: 398, width: 366, height: 104)

        let result = phonePlacement(cutouts: [purchase, fab])

        #expect(result.edge == .above)
        #expect(result.maxHeight == nil)
        let rect = cardRect(result, width: 358, height: 200)
        #expect(!inflated(fab).intersects(rect))
        #expect(!inflated(purchase).intersects(rect))
    }

    @Test func place_TallCutoutOnRegular_PlacesOnSideWithMoreRoom() throws {
        let tall = CGRect(x: 700, y: 60, width: 440, height: 700)

        let result = padPlacement(cutouts: [tall])

        #expect(result.edge == .leading)
        #expect(result.origin.x + 400 == tall.minX - TourCardPlacement.gap)
        #expect(result.maxHeight == nil)
    }

    @Test func place_TallCutoutNearLeadingEdge_PlacesOnTrailingSide() {
        let tall = CGRect(x: 40, y: 60, width: 440, height: 700)

        let result = padPlacement(cutouts: [tall])

        #expect(result.edge == .trailing)
        #expect(result.origin.x == tall.maxX + TourCardPlacement.gap)
    }

    @Test func place_TallCutoutWithoutSideAllowed_ScrollsInsteadOfSide() {
        let tall = CGRect(x: 700, y: 60, width: 440, height: 700)

        let result = padPlacement(cutouts: [tall], allowsSide: false)

        #expect(result.edge == .below || result.edge == .above)
        #expect(result.maxHeight != nil)
    }

    @Test func place_SideCandidate_StaysWithinSafeAreaVertically() {
        let tall = CGRect(x: 700, y: 30, width: 440, height: 90)

        let result = padPlacement(cutouts: [tall], cardHeight: 700)

        let safeTop = padInsets.top + TourCardPlacement.margin
        let safeBottom = pad.height - padInsets.bottom - TourCardPlacement.margin
        #expect(result.origin.y >= safeTop)
        #expect(result.origin.y + 700 <= safeBottom || result.maxHeight != nil)
    }

    @Test func place_CutoutAtLeadingEdge_ClampsCardToMargin() {
        let cutout = CGRect(x: 0, y: 180, width: 44, height: 44)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.origin.x == TourCardPlacement.margin)
    }

    @Test func place_CutoutAtTrailingEdge_ClampsCardToMargin() {
        let cutout = CGRect(x: 346, y: 180, width: 44, height: 44)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.origin.x == phone.width - TourCardPlacement.margin - 358)
    }

    @Test func place_CutoutAtLeadingEdge_ClampsNotchToLeadingClearance() {
        let cutout = CGRect(x: 0, y: 180, width: 44, height: 44)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.notchOffset == TourCardPlacement.notchCornerClearance)
    }

    @Test func place_CutoutAtTrailingEdge_ClampsNotchToTrailingClearance() {
        let cutout = CGRect(x: 346, y: 180, width: 44, height: 44)

        let result = phonePlacement(cutouts: [cutout])

        #expect(result.notchOffset == 358 - TourCardPlacement.notchCornerClearance - TourCardPlacement.notchSize)
    }

    @Test func place_CentredCutout_NotchPointsAtCutoutMidX() {
        let cutout = CGRect(x: 170, y: 180, width: 50, height: 50)

        let result = phonePlacement(cutouts: [cutout])

        let notchCentre = result.origin.x + result.notchOffset + TourCardPlacement.notchSize / 2
        #expect(notchCentre == cutout.midX)
    }

    @Test func place_SidePlacement_NotchOffsetClampedWithinCardHeight() {
        let tall = CGRect(x: 700, y: 60, width: 440, height: 700)

        let result = padPlacement(cutouts: [tall], cardHeight: 200)

        let upper = 200 - TourCardPlacement.notchCornerClearance - TourCardPlacement.notchSize
        #expect(result.notchOffset >= TourCardPlacement.notchCornerClearance)
        #expect(result.notchOffset <= upper)
    }

    @Test(arguments: [
        CGRect(x: 12, y: 100, width: 366, height: 52),
        CGRect(x: 12, y: 400, width: 366, height: 100),
        CGRect(x: 12, y: 700, width: 366, height: 60)
    ])
    func place_AnyCutout_CardStaysInsideSafeArea(cutout: CGRect) {
        let result = phonePlacement(cutouts: [cutout])

        let rect = cardRect(result, width: 358, height: 200)
        #expect(rect.minY >= phoneInsets.top + TourCardPlacement.margin)
        #expect(rect.maxY <= phone.height - phoneInsets.bottom - TourCardPlacement.margin)
        #expect(rect.minX >= TourCardPlacement.margin)
        #expect(rect.maxX <= phone.width - TourCardPlacement.margin)
    }

    @Test func place_NoRoomAnywhere_ReturnsMaxHeightAndAvoidsCutout() throws {
        let cutout = CGRect(x: 12, y: 330, width: 366, height: 300)

        let result = phonePlacement(cutouts: [cutout], cardHeight: 400)

        let maxHeight = try #require(result.maxHeight)
        #expect(maxHeight < 400)
        let rect = cardRect(result, width: 358, height: 400)
        #expect(!inflated(cutout).intersects(rect))
        #expect(rect.minY >= phoneInsets.top + TourCardPlacement.margin)
        #expect(rect.maxY <= phone.height - phoneInsets.bottom - TourCardPlacement.margin)
    }

    @Test func place_NoRoomWithTwoCutouts_CardAvoidsBoth() throws {
        let primary = CGRect(x: 12, y: 160, width: 366, height: 300)
        let second = CGRect(x: 12, y: 520, width: 366, height: 250)

        let result = phonePlacement(cutouts: [primary, second], cardHeight: 500)

        let maxHeight = try #require(result.maxHeight)
        let rect = cardRect(result, width: 358, height: 500)
        #expect(maxHeight > 0)
        #expect(!inflated(primary).intersects(rect))
        #expect(!inflated(second).intersects(rect))
    }

    @Test func place_NoRoomOnRegularWithSide_PrefersLargestFreeSpace() throws {
        let wide = CGRect(x: 40, y: 80, width: 1100, height: 640)

        let result = padPlacement(cutouts: [wide], cardHeight: 600)

        let rect = cardRect(result, width: 400, height: 600)
        #expect(!inflated(wide).intersects(rect))
        #expect(result.maxHeight != nil)
    }

    @Test func place_NoCutouts_ReturnsCardInsideSafeArea() {
        let result = phonePlacement(cutouts: [])

        #expect(result.origin.x >= TourCardPlacement.margin)
        #expect(result.origin.y >= phoneInsets.top + TourCardPlacement.margin)
        #expect(result.maxHeight == nil)
    }
}
