import SwiftUI

/// A name in `ink` on the leading edge and a value on the trailing edge,
/// read by VoiceOver as one element. `below` sits under the name, where a
/// row's status stamps go. At accessibility text sizes the value moves under
/// the name instead of splitting both mid-word.
struct HoneyLedgerLabeledRow<Value: View, Below: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    @ViewBuilder let value: Value
    @ViewBuilder let below: Below

    init(_ title: String, @ViewBuilder value: () -> Value, @ViewBuilder below: () -> Below) {
        self.title = title
        self.value = value()
        self.below = below()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.ink)
            below
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    label
                    Spacer(minLength: 8)
                    value
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension HoneyLedgerLabeledRow where Below == EmptyView {
    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.init(title, value: value, below: { EmptyView() })
    }
}
