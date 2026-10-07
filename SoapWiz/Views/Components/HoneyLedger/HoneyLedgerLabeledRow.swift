import SwiftUI

/// A name in `ink` on the leading edge and a value on the trailing edge,
/// read by VoiceOver as one element.
struct HoneyLedgerLabeledRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            value
        }
        .accessibilityElement(children: .combine)
    }
}
