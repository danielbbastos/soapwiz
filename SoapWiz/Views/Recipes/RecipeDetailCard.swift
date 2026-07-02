import SwiftUI

/// Mimics an inset-grouped Form section as a free-standing card, for the
/// side-by-side regions of the regular-width recipe detail layout.
struct RecipeDetailCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.cardBackground, in: .rect(cornerRadius: 26))
        }
    }
}
