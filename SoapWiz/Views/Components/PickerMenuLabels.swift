import SwiftUI

/// Row label that mimics a Form menu-picker: title on the left, the current
/// value on the right, with the up/down chevrons affordance. Used as the label
/// for a `Menu` that doubles as a picker plus an inline "New …" action.
///
/// `isPlaceholder` marks a value that stands for nothing chosen, such as
/// "None", and draws it in `inkFaint`. At accessibility text sizes the value
/// moves under the title instead of splitting both mid-word.
struct PickerMenuRowLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String
    var isPlaceholder = false

    private var titleText: some View {
        Text(title)
            .foregroundStyle(Color.ink)
    }

    private var valueAndChevrons: some View {
        HStack {
            Text(value)
                .fontWeight(isPlaceholder ? .regular : .medium)
                .foregroundStyle(isPlaceholder ? Color.inkFaint : Color.ink)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(Color.inkSoft)
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueAndChevrons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                titleText
                Spacer()
                valueAndChevrons
            }
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
