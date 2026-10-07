import Testing
import UIKit
@testable import SoapWiz

@Suite
struct MenuColumnPaddingTests {

    private let font = UIFont.systemFont(ofSize: 17)

    private var step: CGFloat {
        MenuColumnPadding.width(of: String(MenuColumnPadding.hairSpace), in: font)
    }

    @Test func padded_EmptyInput_ReturnsEmpty() {
        #expect(MenuColumnPadding.padded([], font: font).isEmpty)
    }

    @Test func padded_SingleEntry_ReturnsItUnchanged() {
        #expect(MenuColumnPadding.padded(["ml"], font: font) == ["ml"])
    }

    @Test func padded_WidestEntry_GetsNoPadding() {
        let padded = MenuColumnPadding.padded(["g", "ml", "L"], font: font)
        #expect(padded[1] == "ml")
    }

    @Test func padded_KeepsOrderAndPrefixes() {
        let entries = ["g", "kg", "oz", "lb", "ml", "L", "un"]
        let padded = MenuColumnPadding.padded(entries, font: font)
        #expect(padded.count == entries.count)
        for (entry, result) in zip(entries, padded) {
            #expect(result.hasPrefix(entry))
            #expect(result.dropFirst(entry.count).allSatisfy { $0 == MenuColumnPadding.hairSpace })
        }
    }

    @Test func padded_EntriesEndWithinHalfAHairSpaceOfTheWidest() {
        let entries = ["g", "kg", "oz", "lb", "ml", "L", "un"]
        let widest = entries.map { MenuColumnPadding.width(of: $0, in: font) }.max() ?? 0
        for result in MenuColumnPadding.padded(entries, font: font) {
            let width = MenuColumnPadding.width(of: result, in: font)
            #expect(abs(width - widest) <= step / 2 + 0.01)
        }
    }

    @Test func padded_EqualWidths_AddsNoPadding() {
        #expect(MenuColumnPadding.padded(["ab", "ab"], font: font) == ["ab", "ab"])
    }
}
