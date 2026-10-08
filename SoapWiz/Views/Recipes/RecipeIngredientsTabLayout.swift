import SwiftUI

/// The height the Ingredients tab's list is given, which caps the expanded
/// cost breakdown bar.
struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
