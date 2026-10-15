import SwiftUI

/// A calculated-amounts row's advisory note, set under the whole row at full
/// width and kept regular weight inside a semibold total.
struct CalculatedAmountNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .fontWeight(.regular)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
