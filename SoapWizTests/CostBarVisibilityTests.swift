import Testing
import CoreGraphics
@testable import SoapWiz

@Suite
struct CostBarVisibilityTests {

    private static let screen = CGRect(x: 0, y: 0, width: 1194, height: 834)

    @Test func hidesCostBar_EditingDockedCollapsed_ReturnsTrue() {
        #expect(CostBreakdownBarInset.hidesCostBar(isEditing: true, dockedKeyboard: true, isExpanded: false))
    }

    @Test(arguments: [
        (false, false, false), (false, true, false), (true, false, false),
        (true, true, true), (false, true, true), (true, false, true)
    ])
    func hidesCostBar_NotEditingDockedAndCollapsed_ReturnsFalse(
        isEditing: Bool, dockedKeyboard: Bool, isExpanded: Bool
    ) {
        #expect(!CostBreakdownBarInset.hidesCostBar(
            isEditing: isEditing, dockedKeyboard: dockedKeyboard, isExpanded: isExpanded
        ))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 406, width: 1194, height: 428),
        CGRect(x: 76.5, y: 406, width: 1194, height: 428),
        CGRect(x: 0, y: 406.5, width: 1193.5, height: 428)
    ])
    func isDockedKeyboard_FullWidthReachingBottom_ReturnsTrue(frame: CGRect) {
        #expect(CostBreakdownBarInset.isDockedKeyboard(frame: frame, screenBounds: Self.screen))
    }

    @Test(arguments: [
        CGRect(x: 331.6, y: 126.2, width: 334, height: 434),
        CGRect(x: 0, y: 834, width: 1194, height: 428),
        CGRect(x: 0, y: 406, width: 1194, height: 300),
        .zero
    ])
    func isDockedKeyboard_FloatingHiddenOrEmpty_ReturnsFalse(frame: CGRect) {
        #expect(!CostBreakdownBarInset.isDockedKeyboard(frame: frame, screenBounds: Self.screen))
    }

    @Test func isDockedKeyboard_EmptyScreen_ReturnsFalse() {
        let frame = CGRect(x: 0, y: 406, width: 1194, height: 428)
        #expect(!CostBreakdownBarInset.isDockedKeyboard(frame: frame, screenBounds: .zero))
    }

    @Test func barOffset_FloatingKeyboardShrunkContainer_MovesBarDown() {
        #expect(Self.offset(containerMaxY: 547) == 267)
    }

    @Test func barOffset_AtRest_IsZero() {
        #expect(Self.offset(containerMaxY: 814) == 0)
    }

    @Test func barOffset_ContainerBelowTarget_NeverNegative() {
        #expect(Self.offset(containerMaxY: 900) == 0)
    }

    @Test func barOffset_DockedKeyboard_IsZero() {
        #expect(Self.offset(containerMaxY: 406, docked: true) == 0)
    }

    @Test func barOffset_TabAboveTabBar_IsZero() {
        #expect(Self.offset(containerMaxY: 745, pins: false) == 0)
    }

    private static func offset(containerMaxY: CGFloat, docked: Bool = false, pins: Bool = true) -> CGFloat {
        CostBreakdownBarInset.barOffset(
            containerMaxY: containerMaxY,
            windowSafeMaxY: 814,
            dockedKeyboard: docked,
            pinsToWindowBottom: pins
        )
    }
}
