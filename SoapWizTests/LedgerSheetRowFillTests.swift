import SwiftUI
import Testing
@testable import SoapWiz

@Suite
struct LedgerSheetRowFillTests {

    @Test func fill_NotSelectedNotPressed_IsRaised() {
        #expect(LedgerSheetRowFill(isSelected: false, isPressed: false) == .raised)
    }

    @Test func fill_PressedNotSelected_IsPressed() {
        #expect(LedgerSheetRowFill(isSelected: false, isPressed: true) == .pressed)
    }

    @Test func fill_SelectedNotPressed_IsSelected() {
        #expect(LedgerSheetRowFill(isSelected: true, isPressed: false) == .selected)
    }

    @Test func fill_SelectedAndPressed_StaysSelected() {
        #expect(LedgerSheetRowFill(isSelected: true, isPressed: true) == .selected)
    }

    @Test func color_EachFill_IsDistinct() {
        let colors = [LedgerSheetRowFill.raised, .pressed, .selected].map(\.color)
        #expect(colors[0] != colors[1])
        #expect(colors[1] != colors[2])
        #expect(colors[0] != colors[2])
    }

    @Test func color_Pressed_IsPreMixedHoneyPressed() {
        #expect(LedgerSheetRowFill.pressed.color == Color.honeyPressed)
    }

    @Test func color_Selected_IsHoney() {
        #expect(LedgerSheetRowFill.selected.color == Color.honey)
    }
}
