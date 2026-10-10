import SwiftUI

extension View {
    /// Lays a menu picker out at the height of the line of text beside it, so
    /// a row holding one is no taller than a row with a plain label. The
    /// picker still draws and takes taps at full size.
    func menuPickerLineHeight() -> some View {
        // What a menu picker adds above and below its value: 34pt tall
        // against a 20pt line of body text.
        let verticalInset: CGFloat = 7
        return padding(.vertical, -verticalInset)
    }
}
