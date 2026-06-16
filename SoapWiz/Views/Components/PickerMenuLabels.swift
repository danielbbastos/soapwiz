import SwiftUI

/// Row label that mimics a Form menu-picker: title on the left, the current
/// value on the right, with the up/down chevrons affordance. Used as the label
/// for a `Menu` that doubles as a picker plus an inline "New …" action.
struct PickerMenuRowLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A menu item that shows a leading checkmark when it is the selected option,
/// matching the native picker selection affordance.
struct MenuSelectionLabel: View {
    let title: String
    let isSelected: Bool

    init(_ title: String, isSelected: Bool) {
        self.title = title
        self.isSelected = isSelected
    }

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
