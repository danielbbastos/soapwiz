import UIKit

/// Lines up a column in a system menu, which takes plain text only: no tab
/// stops, no fixed-width font. Each entry is padded with hair spaces to the
/// width of the widest, measured in the menu's own font, so whatever follows
/// it starts at the same place to within a hair space.
enum MenuColumnPadding {
    static let hairSpace: Character = "\u{200A}"

    /// The menu's item font. Measuring at the current text size keeps the
    /// padding right as Dynamic Type grows the menu.
    static var menuFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }

    static func padded(_ entries: [String], font: UIFont = menuFont) -> [String] {
        let widths = entries.map { width(of: $0, in: font) }
        guard let widest = widths.max() else { return [] }
        let step = width(of: String(hairSpace), in: font)
        guard step > 0 else { return entries }
        return zip(entries, widths).map { entry, entryWidth in
            let count = Int(((widest - entryWidth) / step).rounded())
            return entry + String(repeating: hairSpace, count: count)
        }
    }

    static func width(of text: String, in font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
